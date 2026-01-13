#!/bin/bash

# This script creates the necessary tables for the Incident Management module.

# Source database configuration
MIGRATION_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$MIGRATION_DIR/db_config.sh"

# SQL commands to create the tables
SQL=""
SQL+="CREATE TABLE incident_management ("
SQL+="    id SERIAL PRIMARY KEY,"
SQL+="    ticket_id INTEGER NOT NULL,"
SQL+="    incident_number VARCHAR(20) UNIQUE NOT NULL,"
SQL+="    created_time TIMESTAMP NOT NULL,"
SQL+="    created_by INTEGER NOT NULL"
SQL+=");

"
SQL+="CREATE TABLE incident_work_notes ("
SQL+="    id SERIAL PRIMARY KEY,"
SQL+="    ticket_id INTEGER NOT NULL,"
SQL+="    note_text TEXT NOT NULL,"
SQL+="    include_in_msi BOOLEAN DEFAULT FALSE,"
SQL+="    created_time TIMESTAMP NOT NULL,"
SQL+="    created_by INTEGER NOT NULL,"
SQL+="    created_by_name VARCHAR(200)"
SQL+=");

"
SQL+="CREATE TABLE incident_resolution_notes ("
SQL+="    id SERIAL PRIMARY KEY,"
SQL+="    ticket_id INTEGER NOT NULL,"
SQL+="    resolution_cat1 VARCHAR(200),"
SQL+="    resolution_cat2 VARCHAR(200),"
SQL+="    resolution_cat3 VARCHAR(200),"
SQL+="    resolution_code VARCHAR(50),"
SQL+="    resolution_notes TEXT,"
SQL+="    created_time TIMESTAMP NOT NULL,"
SQL+="    created_by INTEGER NOT NULL,"
SQL+="    created_by_name VARCHAR(200)"
SQL+=");"

# Execute the SQL commands
run_psql -c "$SQL"

# Check if the tables were created successfully
if [ $? -eq 0 ]; then
    echo "Tables created successfully."
else
    echo "Error creating tables."
fi