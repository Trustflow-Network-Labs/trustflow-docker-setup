-- login as postgres
DROP DATABASE IF EXISTS trustflow;
DROP ROLE IF EXISTS trustflow;
-- login as postgres
\set POSTGRESQL_PASSWORD `echo "$POSTGRESQL_PASSWORD"`
CREATE ROLE trustflow WITH LOGIN PASSWORD :'POSTGRESQL_PASSWORD';
SELECT 'CREATE DATABASE trustflow OWNER trustflow'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'trustflow')\gexec
\c trustflow
SET ROLE trustflow;
SET SESSION AUTHORIZATION trustflow;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS trustflow_node AUTHORIZATION trustflow;
CREATE SCHEMA IF NOT EXISTS trustflow_shared AUTHORIZATION trustflow;
-- Full text search update / trigger function
--
--DROP FUNCTION IF EXISTS trustflow_shared.update_full_text_search();
CREATE OR REPLACE FUNCTION trustflow_shared.update_full_text_search() RETURNS TRIGGER AS $update_full_text_search$
	DECLARE
		considered_columns VARCHAR[] = regexp_split_to_array(TG_ARGV[4], '\|\|\|');
		counter SMALLINT = 1;
		no_of_columns SMALLINT = array_length(considered_columns , 1);
		fts VARCHAR = '';
	BEGIN
		WHILE counter <= no_of_columns LOOP
			fts = concat(fts, format(' COALESCE(translate(NULLIF(cast("%s" AS TEXT),''''),''/.-*'',''    ''),'''') ', considered_columns[counter]));
			IF (counter < no_of_columns) THEN
				fts = concat(fts, ' || '' '' || ');
			END IF;
			counter = counter + 1;
		END LOOP;
		EXECUTE format('UPDATE %s SET %s = to_tsvector(''%s'', %s) WHERE "id" = ''%s'';', concat('"', TG_ARGV[0], '"."', TG_ARGV[1], '"'), concat('"', TG_ARGV[3], '"'), TG_ARGV[2], fts, NEW.id);
		RETURN NULL; -- result will be ignored since this is AFTER trigger function
	END;
$update_full_text_search$ LANGUAGE plpgsql;
-- Nodes
--
--DROP TABLE IF EXISTS trustflow_node.nodes;
CREATE TABLE IF NOT EXISTS trustflow_node.nodes (
	"id" SERIAL PRIMARY KEY,
	"node_id" VARCHAR(255) NOT NULL,
	"multiaddrs" TEXT[] NOT NULL,
	"self" BOOLEAN DEFAULT FALSE
);
CREATE UNIQUE INDEX IF NOT EXISTS nodes_id_idx ON trustflow_node.nodes ("id");
CREATE INDEX IF NOT EXISTS nodes_node_id_idx ON trustflow_node.nodes ("node_id");
CREATE INDEX IF NOT EXISTS nodes_multiaddrs_idx ON trustflow_node.nodes USING GIN ("multiaddrs");

-- Find itself
--
DROP TYPE IF EXISTS trustflow_node.response_find_itself CASCADE;
CREATE TYPE trustflow_node.response_find_itself AS ("id" INTEGER, "node_id" VARCHAR(255), "multiaddrs" TEXT[], "self" BOOLEAN);

--DROP FUNCTION IF EXISTS trustflow_node.find_itself();
CREATE OR REPLACE FUNCTION trustflow_node.find_itself() RETURNS trustflow_node.response_find_itself AS $find_itself$
	DECLARE
		response trustflow_node.response_find_itself;
	BEGIN
		-- look for node address / id
		SELECT "id", "node_id", "multiaddrs", "self"
		INTO response.id, response.node_id, response.multiaddrs, response.self
		FROM trustflow_node.nodes WHERE "self" = TRUE;
		return response;
	END;
$find_itself$ LANGUAGE plpgsql;

-- Add node
--
DROP TYPE IF EXISTS trustflow_node.response_add_node CASCADE;
CREATE TYPE trustflow_node.response_add_node AS ("id" INTEGER, "node_id" VARCHAR(255), "multiaddrs" TEXT[], "self" BOOLEAN);

--DROP FUNCTION IF EXISTS trustflow_node.add_node(IN the_node_id VARCHAR(255), IN the_multiaddrs TEXT[], IN the_self BOOLEAN);
CREATE OR REPLACE FUNCTION trustflow_node.add_node(IN the_node_id VARCHAR(255), IN the_multiaddrs TEXT[], IN the_self BOOLEAN) RETURNS trustflow_node.response_add_node AS $add_node$
	DECLARE
		response trustflow_node.response_add_node;
	BEGIN
		-- check if node already exists
		SELECT "id" INTO response.id FROM trustflow_node.nodes WHERE "node_id" = the_node_id;
		IF (response.id IS NULL) THEN
			-- add node
			INSERT INTO trustflow_node.nodes ("node_id", "multiaddrs", "self")
			VALUES (the_node_id, the_multiaddrs, the_self) RETURNING "id" INTO response.id;
			response.node_id = the_node_id;
			response.multiaddrs = the_multiaddrs;
			response.self = the_self;
		ELSE
			-- update node
			UPDATE trustflow_node.nodes
			SET "node_id" = the_node_id, "multiaddrs" = the_multiaddrs, "self" = the_self
			WHERE "id" = response.id;
			response.node_id = the_node_id;
			response.multiaddrs = the_multiaddrs;
			response.self = the_self;
		END IF;
		return response;
	END;
$add_node$ LANGUAGE plpgsql;
-- Keystore
--
--DROP TABLE IF EXISTS trustflow_node.keystore;
CREATE TABLE IF NOT EXISTS trustflow_node.keystore (
	"id" SERIAL PRIMARY KEY,
	"identifier" VARCHAR(255) NOT NULL,
	"algorithm" VARCHAR(255) NOT NULL,
	"key" BYTEA NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS keystore_id_idx ON trustflow_node.keystore ("id");
CREATE INDEX IF NOT EXISTS keystore_identifier_idx ON trustflow_node.keystore ("identifier");
CREATE INDEX IF NOT EXISTS keystore_algorithm_idx ON trustflow_node.keystore ("algorithm");

-- Find a key
--
DROP TYPE IF EXISTS trustflow_node.response_find_key CASCADE;
CREATE TYPE trustflow_node.response_find_key AS ("id" INTEGER, "identifier" VARCHAR(255), "algorithm" VARCHAR(255), "key" BYTEA);

--DROP FUNCTION IF EXISTS trustflow_node.find_key(IN the_identifier VARCHAR(255));
CREATE OR REPLACE FUNCTION trustflow_node.find_key(IN the_identifier VARCHAR(255)) RETURNS trustflow_node.response_find_key AS $find_key$
	DECLARE
		response trustflow_node.response_find_key;
	BEGIN
		-- look for a key by provided indentifier
		SELECT "id", "identifier", "algorithm", "key"
		INTO response.id, response.identifier, response.algorithm, response.key
		FROM trustflow_node.keystore WHERE "identifier" = the_identifier;
		return response;
	END;
$find_key$ LANGUAGE plpgsql;

-- Add a key
--
DROP TYPE IF EXISTS trustflow_node.response_add_key CASCADE;
CREATE TYPE trustflow_node.response_add_key AS ("id" INTEGER, "identifier" VARCHAR(255), "algorithm" VARCHAR(255), "key" BYTEA);

--DROP FUNCTION IF EXISTS trustflow_node.add_key(IN the_identifier VARCHAR(255), IN the_algorithm VARCHAR(255), IN the_key BYTEA);
CREATE OR REPLACE FUNCTION trustflow_node.add_key(IN the_identifier VARCHAR(255), IN the_algorithm VARCHAR(255), IN the_key BYTEA) RETURNS trustflow_node.response_add_key AS $add_key$
	DECLARE
		response trustflow_node.response_add_key;
	BEGIN
		-- check if the key already exists
		SELECT "id" INTO response.id FROM trustflow_node.keystore WHERE "identifier" = the_identifier;
		IF (response.id IS NULL) THEN
			-- add key
			INSERT INTO trustflow_node.keystore ("identifier", "algorithm", "key")
			VALUES (the_identifier, the_algorithm, the_key) RETURNING "id" INTO response.id;
			response.identifier = the_identifier;
			response.algorithm = the_algorithm;
			response.key = the_key;
		ELSE
			-- update key
			UPDATE trustflow_node.keystore
			SET "identifier" = the_identifier, "algorithm" = the_algorithm, "key" = the_key
			WHERE "id" = response.id;
			response.identifier = the_identifier;
			response.algorithm = the_algorithm;
			response.key = the_key;
		END IF;
		return response;
	END;
$add_key$ LANGUAGE plpgsql;
-- Service catalogue
--
--DROP TABLE IF EXISTS trustflow_node.service_catalogue;
CREATE TABLE IF NOT EXISTS trustflow_node.service_catalogue (
	"id" SERIAL PRIMARY KEY,
	"type" VARCHAR(255) NOT NULL,
	"name" VARCHAR(255) NOT NULL,
	"description" TEXT DEFAULT NULL,
	"price" DOUBLE PRECISION DEFAULT 0.0,
	"node_id" INTEGER NOT NULL,
	CONSTRAINT fk_trustflow_node_nodes_node_id
		FOREIGN KEY("node_id")
		REFERENCES trustflow_node.nodes("id")
);
CREATE UNIQUE INDEX IF NOT EXISTS service_catalogue_id_idx ON trustflow_node.service_catalogue ("id");
CREATE INDEX IF NOT EXISTS service_catalogue_name_idx ON trustflow_node.service_catalogue ("name");
