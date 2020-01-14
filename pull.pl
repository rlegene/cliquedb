#!/usr/bin/perl -w
# 20200108 Robert Martin-Legene <robert@martin-legene.dk>
use     warnings;
use     strict;
use     Data::Dumper;
use     Math::BigInt;
use     LWP;
use     JSON;
use	Net::DNS;
use	Net::DNS::Resolver;
use     DBI;
use     Carp;
$Carp::Verbose  =   1;

# 47525974938;
my      $netversion         =   Math::BigInt->new( "0xb10c4d39a" );
# 200941592
my      $chainid            =   Math::BigInt->new( "0xbfa2018"   );
my      $idcounter          =   0;
my      $ua;
my      @endpoints;
my      @blockqueue;
my      %sealers;
# Set maxruns to 1 if you want to just do a single run to keep
# your database up-to-date.
my      $maxruns            =   0;
# db stuff
my      $dbh;
my      $sth_insertBlock;
my      $sth_selectBlockByHash;
my      $sth_selectTransactionByHash;
my      $sth_insertTransaction;
my      $sth_insertTransactionWithContractAddress;
my      $sth_insertsealer;
my      $sth_selectsealer;
my      $sth_updatewhosealed;
my      $sth_selectmaxunknownsigned;

sub     info(@)
{
    # if 1 param only
    unshift @_, '%s'
        if $#_ == 0;
    my      $format         =   shift;
    $format                 =   "%s: " . $format;
    printf  $format, astime(time), @_;
}

sub     astime
{
    my  @t                  =   localtime( $_[0] );
    $t[5]                   +=  1900;
    $t[4]                   +=  1;
    return sprintf '%04d%02d%02d-%02d%02d%02d', @t[5,4,3,2,1,0];
}

sub     shorthash($)
{
    local   $_              =   $_[0];
    s/^(0x.......).*(.......)$/$1..$2/;
    return $_;
}

sub     rpcreq
{
    my  ( $endpoint,
        $opname, @params )  =   @_;
    # $ua->ssl_opts( 'verify_hostname' => 0 );
    my      %args           =   (
        jsonrpc             =>  '2.0',
        method              =>  $opname,
        id                  =>  $idcounter++,
    );
    my  @args               =   map {
            my  $v          =   $args{$_};
            $v              =   qq/"${v}"/ if $v !~ /^\d+$/;
            sprintf qq/"%s":%s/, $_, $v;
        } keys %args;
    if ( scalar @params )
    {
        my  $p              =   '"params":[';
        foreach my $param ( @params )
        {
            $param = '"' . $param . '"'
                if  $param ne 'true'
                and $param ne 'false'
                and $param !~ /^\d+$/;
            $p              .=  $param . ',';
        }
        chop $p;
        $p                  .=  ']';
        push @args, $p;
    }
    my  $args               =   '{' . join(',',@args) . '}';
    my  $res                =   $ua->post(
        $endpoint,
        'Content-Type'      =>  'application/json',
        'Content'           =>  $args,
    );
    die $res->status_line
        unless $res->is_success;
    my  $json               =   decode_json($res->content);
    return $json->{'result'};
}

sub     endpoint_find
{
    my      @endpoints;
    my      $networknumber  =   $netversion->bstr;
    my      $res            =   Net::DNS::Resolver->new();
    my      $origin         =   'bfa.martin-legene.dk';
    my      $fqdn           =   sprintf
        '_rpc._tcp.public.%s.%s.',
        $networknumber, $origin;
    my	    $reply          =   $res->query( $fqdn, 'SRV' );
    die "No SRV RR found for public endpoints. Stopped"
        if not $reply;
    my      @answer;
    @answer                 =   rrsort( 'SRV', 'priority', $reply->answer );
    die "DNS SRV query returned no SRV records. Stopped"
        if not @answer;
    my  %protolookup        =   (
        '_rpc'              =>  'http',
        '_rpcs'             =>  'https',
    );
    foreach my $answer ( @answer )
    {
        my      $targetname =   $answer->target;
        info "Publicly open endpoint found at %s.\n", $targetname;
        my      $r_a        =   $res->query( $targetname, 'A'    );
        my      $r_aaaa     =   $res->query( $targetname, 'AAAA' );
        my      @addresses  =   ();
        push @addresses, rrsort( 'A',    $r_a->answer )
            if $r_a;
        push @addresses, rrsort( 'AAAA', $r_aaaa->answer )
            if $r_aaaa;
        warn "No address found for $targetname,"
            if not @addresses;
        my      $label1     =   (split( /\./, $fqdn, 2 ))[0];
        foreach my $address_rr ( @addresses )
        {
            next
                if not exists $protolookup{$label1};
            my $proto       =   $protolookup{$label1};
            push @endpoints, sprintf(
                '%s://%s:%s',
                $proto,
                $address_rr->address,
                $answer->port
            );
        }
    }
    info "Preferring endpoint at %s\n", $endpoints[0];
    return  @endpoints;
}

sub     getblock
{
    my      $blockid        =   $_[0];
    my      $json;
    $blockid                =   Math::BigInt->new( $blockid )
        if ref($blockid) eq ''
        and $blockid =~ /^\d+$/;
    if ( ref $blockid eq 'Math::BigInt' )
    {
        $json               =   rpcreq(
            $endpoints[0],
            'eth_getBlockByNumber',
            $blockid->as_hex, 'false' );
    }
    else
    {
        $sth_selectBlockByHash->execute( $blockid );
        return if $sth_selectBlockByHash->fetch;
        $json               =   rpcreq(
            $endpoints[0],
            'eth_getBlockByHash',
            $blockid, 'false'
        );
    }
    die "We should have received some kind of JSON from our RPC call, " .
        "but apparently not. Stopped "
        if not defined $json;
    $sth_selectBlockByHash->execute( $json->{'hash'} );
    return if $sth_selectBlockByHash->fetch;
    foreach my $key (qw(
        timestamp gasUsed gasLimit difficulty number totalDifficulty size
    )) {
        $json->{$key}       =   Math::BigInt->new( $json->{$key} )->bstr
            if exists $json->{$key};
    }
    info "%s %s %s %s %s %s/%s\n",
        shorthash $json->{'hash'},
        astime($json->{'timestamp'}),
        $json->{'number'},
        $json->{'difficulty'},
        $json->{'size'},
        $json->{'gasUsed'},
        $json->{'gasLimit'};
    $sth_insertBlock->execute(
        lc $json->{'hash'},
        lc $json->{'parentHash'},
        $json->{'number'},
        $json->{'timestamp'},
        $json->{'difficulty'},
        $json->{'gasUsed'},
        $json->{'gasLimit'},
        $json->{'size'}
    );
    if ( scalar @{$json->{'transactions'}} )
    {
        foreach my $txhash ( reverse @{ $json->{'transactions'} } )
        {
            getTransByHash( $txhash );
        }
    }
    unshift @blockqueue, lc $json->{'parentHash'}
        if $json->{'number'} != 0;
}

sub     getTransByHash
{
    my  $hash               =   $_[0];
    $sth_selectTransactionByHash->execute( $hash );
    return if $sth_selectTransactionByHash->fetch;
    my  $json               =   rpcreq(
        $endpoints[0],
        'eth_getTransactionByHash',
        $hash
    );
    my  $rcpt               =   rpcreq(
        $endpoints[0],
        'eth_getTransactionReceipt',
        $hash
    );
    die if not $rcpt;
    $json->{'status'}       =   $rcpt->{'status'};
    $json->{'gasUsed'}      =   $rcpt->{'gasUsed'};
    $json->{'contractAddress'}
                            =   $rcpt->{'contractAddress'};
    foreach my $key (qw( nonce value gas gasPrice gasUsed status))
    {
        $json->{$key}       =   Math::BigInt->new( $json->{$key} )->bstr;
    }
    info    "%s %s %s %s %s\n",
            shorthash $json->{'hash'},
            $json->{'nonce'},
            $json->{'value'},
            shorthash $json->{'to'},
            shorthash $json->{'from'};
    my      $input          =   $json->{'input'};
    $input                  =~  s/^0x//;
    my      $inputlen       =   length($input) / 2;
    my      @args           =   (
        lc $json->{'hash'},
        lc $json->{'blockHash'},
        $json->{'nonce'},
        $json->{'gas'},
        $json->{'gasPrice'},
        $json->{'value'},
        lc $json->{'to'},
        lc $json->{'from'},
        $inputlen,
        $json->{'gasUsed'},
        $json->{'status'},
    );
    my  $function           =   $sth_insertTransaction;
    if ( $json->{'contractAddress'} )
    {
        push @args, $json->{'contractAddress'};
        $function           =   $sth_insertTransactionWithContractAddress;
    }
    $function->execute( @args );
}

sub     getTransRcptByHash
{
    my  $hash               =   $_[0];
}

sub     versioncheck
{
    my      $n;
    my      $ok             =   1;
    $n                      =   Math::BigInt->new(
        rpcreq( $endpoints[0], "net_version" )
    );
    if ( $n->bcmp( $netversion ) != 0 )
    {
        warn "Network says it has net.version "
            . $n->bstr
            . " ("
            . $n->as_hex
            . "). Expected $netversion ("
            . $netversion->as_hex
            . ").\n";
        $ok                 =   0;
    }
    $n                      =   Math::BigInt->new(
        rpcreq( $endpoints[0], "eth_chainId" )
    );
    if ( $n->bcmp( $chainid ) != 0 )
    {
        warn "Network says it has eth.chainId "
            . $n->bstr
            . " ("
            . $n->as_hex
            . "). Expected $chainid ("
            . $chainid->as_hex
            . ").\n";
        $ok                 =   0;
    }
    exit 1 if not $ok;
    return $ok;
}

sub     sealer
{
    my      $hash           =   $_[0];
    my      $row;
    die unless defined $hash;
    return $sealers{$hash} if exists $sealers{$hash};
    $sth_selectsealer->execute( $hash );
    return $sealers{$hash} = $row->[0] if $row = $sth_selectsealer->fetch;
    $sth_insertsealer->execute( $hash );
    $sth_selectsealer->execute( $hash );
    die     "Apparently we failed to get find/create a new sealer. Stopped"
        if not $row = $sth_selectsealer->fetch;
    return $sealers{$hash} = $row->[0];
}

sub     getsnap
{
    my      $number         =   $_[0];
    $number                 =   Math::BigInt->new( $number )
        if ref($number) ne 'Math::BigInt';
    my      $json           =   rpcreq(
        $endpoints[0],
        'clique_getSnapshot',
        $number->as_hex
    );
    return if not defined $json;
    info    "Snapshot at block # %s.\n", $number;
    my      $recents        =   $json->{'recents'};
    return if not defined $recents;
    my      $hash           =   $json->{'hash'};
    my      $count          =   0;
    while ( exists $recents->{$number->bstr} )
    {
        $sth_selectBlockByHash->execute( $hash );
        my  $row            =   $sth_selectBlockByHash->fetchrow_hashref;
        return if not defined $row;
        my  $newnumber      =   Math::BigInt->new( $row->{'number'} );
        return if $newnumber->bcmp($number) != 0;
        # Stop if we got to a block with sealers.
        return if defined $row->{'sealer'};
        my  $sealerhash     =   $recents->{$number->bstr};
        return if not defined $sealerhash;
        my  $internalid     =   sealer( $sealerhash );
        return if not defined $internalid;
        my $rows_affected   =   $sth_updatewhosealed->execute(
            $internalid,
            $hash
        );
        # For next block...
        $hash               =   $row->{'parentHash'};
        $number->bsub(1);
    }
    return  $number;
}

sub     allsnaps
{
    $sth_selectmaxunknownsigned->execute();
    my      $unkn           =   $sth_selectmaxunknownsigned->fetchrow_hashref;
    my      $number         =   Math::BigInt->new( $unkn->{'number'} );
    my      $committer      =   0;
    while ( defined $number and not $number->is_zero )
    {
        $number             =   getsnap( $number );
        $dbh->commit
            if ( $committer++ % 75 ) == 0;
    }
    $dbh->commit;
}

sub     highest
{
    info    "Looking for the highest block number in the blockchain.\n";
    my      $n              =   Math::BigInt->new(
        rpcreq( $endpoints[0], "eth_blockNumber" )
    );
    info    "The highest block number is %s\n", $n->bstr;
    return $n;
}

sub     main
{
    $|                      =   1;
    info                        "Looking for public RPC endpoints of "
                            .   "the BFA.\n";
    $ua                     =   LWP::UserAgent->new( keep_alive => 10 );
    @endpoints              =   endpoint_find();
    versioncheck();
    info                        "Connecting to database and setting up "
                            .   "prepared statements.\n";
    die                         "Database does not exist. Did you run "
                            .   "setup.sh and are you in the right "
                            .   "directory?\n"
        unless                  -f 'bfa.sqlite3';
    $dbh                    =   DBI->connect(
        "dbi:SQLite:dbname=bfa.sqlite3","","",
        {AutoCommit=>0,RaiseError=>1}
    )
        or die                      DBI::errstr;
    $sth_insertBlock        =   $dbh->prepare(q(
        INSERT INTO blocks
        (   hash,       parentHash, number,     timestamp,
            difficulty, gasUsed,    gasLimit,   size        )
        VALUES  (?,?,?,?,?,?,?,?)
    )) or die $DBI::errstr;
    $sth_selectBlockByHash  =   $dbh->prepare(q(
        SELECT  parenthash,number,sealer
        FROM    blocks
        WHERE   hash=?
    )) or die $DBI::errstr;
    $sth_selectTransactionByHash
                            =   $dbh->prepare(q(
        SELECT  "exists"
        FROM    transactions
        WHERE   hash=?
    )) or die $DBI::errstr;
    $sth_insertTransactionWithContractAddress
                            =   $dbh->prepare(q(
        INSERT INTO transactions
        (   hash,       blockHash,  nonce,  gas,
            gasPrice,   value,      _from,  _to,
            inputlen,   gasUsed,    status, contractAddress )
        VALUES  (?,?,?,?,?,?,?,?,?,?,?,?)
    )) or die $DBI::errstr;
    $sth_insertTransaction  =   $dbh->prepare(q(
        INSERT INTO transactions
        (   hash,       blockHash,  nonce,  gas,
            gasPrice,   value,      _from,  _to,
            inputlen,   gasUsed,    status                  )
        VALUES  (?,?,?,?,?,?,?,?,?,?,?)
    )) or die $DBI::errstr;
    my      $sth_selectOrphans
                            =   $dbh->prepare(q(
        SELECT  parentHash,number
        FROM    blocks
        WHERE   parentHash NOT IN (
            SELECT  hash
            FROM    blocks
        )
    )) or die $DBI::errstr;
    $sth_selectsealer       =   $dbh->prepare(q(
        SELECT  internalid
        FROM    sealers
        WHERE   hash=?
    )) or die $DBI::errstr;
    $sth_insertsealer       =   $dbh->prepare(q(
        INSERT INTO sealers
        (   hash    )
        VALUES  (?)
    )) or die $DBI::errstr;
    $sth_updatewhosealed    =   $dbh->prepare(q(
        UPDATE  blocks
        SET     sealer=?
        WHERE   hash=?
        AND     sealer IS NULL
    )) or die $DBI::errstr;
    $sth_selectmaxunknownsigned
                            =   $dbh->prepare(q(
        SELECT  number
        FROM    blocks
        WHERE   number = (
            SELECT  MAX(number)
            FROM    blocks
            WHERE   sealer IS NULL
        )
    )) or die $DBI::errstr;
    info                        "Looking for orphaned blocks in the "
                            .   "database.\n";
    $sth_selectOrphans->execute();
    while ( my $row         =   $sth_selectOrphans->fetch )
    {
        next if $row->[0] =~ /^0x0{64}$/;
        info                    "Found block# %s as an orphan.\n",
                                    $row->[1];
        push @blockqueue, $row->[0]
    }
    while ( --$maxruns != 0 )
    {
        unshift @blockqueue, highest();
        while ( @blockqueue )
        {
            my  $maxinarow      =   2500;
            getblock( shift @blockqueue )
                while @blockqueue and --$maxinarow;
            # Find out who signed all blocks
            allsnaps();
            $dbh->commit;
        }
        sleep 5;
    }
}

main();
