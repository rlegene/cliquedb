#!/bin/bash

trap 'exit 1' ERR

dbfile="bfa.sqlite3"
dumpfile="bfa.dump"

if   [ -e "$dbfile" ]
then
    echo "$dbfile exists. Attempting a backup."
    echo .dump | sqlite3 "$dbfile" > "$dumpfile" || ( rm "$dumpfile" ; false )
elif [ -e "$dumpfile" -a ! -e "$dbfile" ]
then
    sqlite3 "$dbfile" < "$dumpfile"
else
    echo "Setting up an empty database."
    echo '
create table blocks ( hash char(66) primary key, parentHash char(66) not null, number integer not null, sealer INTEGER, timestamp integer, difficulty integer, gasUsed integer, gasLimit integer, size integer );
create index blocknum on blocks(number);
create index blockparenthash on blocks(parentHash);
create index blocktimestamp on blocks(timestamp);
create index blockssealer on blocks(sealer);

CREATE TABLE transactions ( hash char(66) primary key, blockHash char(66), nonce integer, gas integer, gasPrice integer, value integer, _from char(66), _to char(66), inputlen integer, contractAddress char(66), status integer, gasUsed integer);
CREATE INDEX txblockhash on transactions(blockHash);
CREATE INDEX txfrom on transactions(_from);
CREATE INDEX txto on transactions(_to);
CREATE INDEX txcontractaddress on transactions(contractAddress);
CREATE INDEX txstatus on transactions(status);

CREATE TABLE sealers ( internalid INTEGER PRIMARY KEY AUTOINCREMENT, hash char(66) not null , shortname text, name text);
INSERT INTO "sealers" VALUES(1,'0x377ab0cd00744dbb07b369cd5c0872dcd362c8f0','UNER','Universidad Nacional de Entre Rios');
INSERT INTO "sealers" VALUES(2,'0x354779914a94ad428d2b53ae96cce3010bb0ce1e','Redlink','RedLink SA');
INSERT INTO "sealers" VALUES(3,'0x998c2651db6f76ca568c0071667d265bcc1b1e98','ASI','ASI');
INSERT INTO "sealers" VALUES(4,'0x2feb6a8876bd9e2116b47834b977506a08ea77bd','PNA','Prefectura Nacional Argentina');
INSERT INTO "sealers" VALUES(5,'0xd1f17aa41354d58940c300ffd79a200944dda2df','Marandu','Marandu');
INSERT INTO "sealers" VALUES(6,'0x39170a1ce03729d141dfaf8077c08b72c9cfdd0c','IXPBB','IXP Bahia Blanca');
INSERT INTO "sealers" VALUES(7,'0x02665f10cb7b93b4491ac9594d188ef2973c310a','CABASE-MZA','CABASE Mendoza');
INSERT INTO "sealers" VALUES(8,'0x19fe7b9b3a1bebde77c5374c8e13c623e3d1b5b2','ARIU','Asociación Redes de Interconexión Universitaria');
INSERT INTO "sealers" VALUES(9,'0xe70fbc9d6be2fe509e4de7317637d8ee83d4f13c','CABASE-PMY','CABASE Puerto Madryn');
INSERT INTO "sealers" VALUES(10,'0xe191ac3108cb2c5d70d0e978876c048d4ba41b03','ANSV','Agencia Nacional de Seguridad Vial');
INSERT INTO "sealers" VALUES(11,'0xf36475eb25ba0c825455f150b26e24ab9449a443','SRT','Superintendencia de Riesgos del Trabajo');
INSERT INTO "sealers" VALUES(12,'0xd1420aa9dd092f50f68913e9e53b378a68e76ed7','SMGP/OPTIC','Secretaría de Modernización de la Gestión Pública / Oficina Provincial de Tecnologías de la Información y la Comunicación- Gobierno de la Provincia del Neuquén');
INSERT INTO "sealers" VALUES(13,'0x2388d2cdb2cd6e7722b4af39c3bb406dd31f560e','UNR','Universidad Nacional de Rosario');
INSERT INTO "sealers" VALUES(14,'0x342e1d075d820ed3f9d9a05967ec4055ab23fa1e','CABASE','CABASE CABA');
INSERT INTO "sealers" VALUES(15,'0xb3d1209aefbe00c78b2247656e2ddfa9e3897526','Colescriba','Colegio de Escribanos de la Provincia de Buenos Aires');
INSERT INTO "sealers" VALUES(16,'0xa14152753515674ae47453bea5e155a20c4ebabc','UP','Universidad de Palermo');
INSERT INTO "sealers" VALUES(17,'0x97a47d718eab9d660b10de08ef42bd7fd915b783','UNLP','Universidad Nacional de La Plata');
INSERT INTO "sealers" VALUES(18,'0x850b30dc584b39275a7ddcaf74a5c0e211523a30','UM','Ultima Milla');
INSERT INTO "sealers" VALUES(19,'0x609043ebde4a06bd28a1de238848e8f82cca9c23','UNSJ','Universidad Nacional de San Juan');
INSERT INTO "sealers" VALUES(20,'0xb43b53af0db2c3fac788195f4b4dcf2b3d72aa44','IPlan','IPlan');
INSERT INTO "sealers" VALUES(21,'0x46991ada2a2544468eb3673524641bf293f23ccc','UNC','Universidad Nacional de Cordoba');
INSERT INTO "sealers" VALUES(22,'0x401d7a8432caa1025d5f093276cc6ec957b87c00','ONTI','Oficina Nacional de Tecnologias de Informacion');
INSERT INTO "sealers" VALUES(23,'0x91c055c6478bd0ad6d19bcb58f5e7ca7b04e67f1','DGSI','Dirección General de Sistemas Informáticos');
INSERT INTO "sealers" VALUES(24,'0x52f8a89484947cd29903b6f52ec6beda69965e38','CABASE-PSS','CABASE Posadas');
INSERT INTO "sealers" VALUES(25,'0x9b3ac6719b02ec7bb4820ae178d31c0bbda3a4e0','Everis','Everis');
INSERT INTO "sealers" VALUES(26,'0x99d6c9fca2a61d4ecdeb403515eb8508dc560c6b',NULL,NULL);
INSERT INTO "sealers" VALUES(27,'0xc0310a7b3b25f49b11b901a667208a3eda8d7ceb','SyT','SyT');
INSERT INTO "sealers" VALUES(28,'0xabeff859aa6b0fb206d840dbf19de970065d4437','Belatrix','Belatrix');
CREATE INDEX sealershash on sealers (hash);
'       | sqlite3 bfa.sqlite3
fi
