#!/usr/bin/bash


#Check directories, create if does not exist.
[ -d "data" ] || mkdir "data"
[ -d "data/processed" ] || mkdir "data/processed"
[ -d "sql-scripts" ] || mkdir "sql-scripts"


#Check to make sure there are .csv files in data/
#Please be careful if changing $csvs_to_load path below, the script relies on this heavily and there may be unintended outcomes, best bet don't touch it!
csvs_to_load="data/*.csv" # Do not change pleasee. 

if ls $csvs_to_load 1> /dev/null 2>&1; then
	csvs_to_load=$(find data/*.csv)

else
	echo "No .csv files to load, in data/"
	exit 1
fi

#Define files/variables
file_table_script="sql-scripts/tables_create.sql"
file_load_data="sql-scripts/load_csv.sql"
audit_db=$(echo $autosrvdb)
audit_host=$(echo $autosrvhost)
audit_user=$(echo $autosrvuser)
audit_pass=$(echo $autosrvpass)

move_csv_to_processed=true

#Script Sql header additions
echo "USE $audit_db;" > $file_table_script 
echo " " >> $file_table_script

echo "USE $audit_db;" > $file_load_data
echo "" > $file_load_data


for csv_to_load in $(echo $csvs_to_load);do
	$(dos2unix $csv_to_load > /dev/null 2>&1 )

#Hack to fix Headers that contain reserved KeyWord Group
	fix_headers_grp=$(head -1 $csv_to_load  | grep -o "Group" | wc -l)
	COUNTER=$fix_headers_grp
	while (( COUNTER !=  0))
	do
		replace_regex="0,/Group/{s/Group/Grp$COUNTER/}"
		sed -i "$replace_regex" $csv_to_load
     		COUNTER=$[$COUNTER - 1]
	done

#Check if data is enclsoed by ", handled that appropriately
	enclosed_set=""
	csv_enclosed_by=$(head -2 $csv_to_load | tr -dc '"' | wc -c)
	
	if (( csv_enclosed_by > 4 )); then
		enclosed_set="ENCLOSED BY '\"'"
	fi

#Generate Table creation syntax
	table_name=$(echo $csv_to_load | cut -f 1 -d. | cut -f 2 -d / )
	table_headers=$(head -1 $csv_to_load | sed 's/\xEF\xBB\xBF//' | tr -d \" | tr -d '(' | tr -d ')' | tr -d ' ' | tr -d '-' | tr -d '/' )
	table_create_command="CREATE TABLE $table_name ("

	for column in ${table_headers//,/ };do
		column=$(echo $column  )
		table_create_default="TEXT"
		#Maybe revist, thinking dates can stay TEXT format, to much of a headache 
		#date_found=$(echo $column | grep -i date | tr  -d '\n')
		#if [ -z "$date_found" ];then
		#	:
		#else
		#	table_create_default="DATE"
		#fi
		table_create_command="$table_create_command $column $table_create_default,"
	done

	table_create_command=${table_create_command:0:-1}  
	table_create_command="$table_create_command);"
	echo "$table_create_command" >> $file_table_script
	echo ""  >> $file_table_script


#Genrate SQL csv import Syntax
	load_command="load data local infile '$csv_to_load' into table $table_name fields terminated by ','"
        load_command="$load_command $enclosed_set"
        load_command="$load_command lines terminated by '\\n'"
	load_command="$load_command IGNORE 1 LINES"
        load_command="$load_command ( $table_headers );"

         echo $load_command >> $file_load_data
	 echo "" >>  $file_load_data
done


#Process Create Tables and then Load CSV Data
read -p "Create Tables and Load Data? (y/n) " -n 1 -r
echo    #
if [[ $REPLY =~ ^[Yy]$ ]]
then

	mysql  --local-infile=1 --host=$audit_host --database=$audit_db --user=$audit_user --password=$audit_pass < $file_table_script
	mysql  --local-infile=1 --host=$audit_host --database=$audit_db --user=$audit_user --password=$audit_pass <$file_load_data    
	
	if  $move_csv_to_processed  ; then

		read -p "Are you sure, 'move *.csv to data/processed'? (y/n) " -n 1 -r
                echo    #

                if [[ $REPLY =~ ^[Yy]$ ]]
                then
			for csv_to_move in $(echo $csvs_to_load);do
				echo "Moving $csv_to_move to data/processed"
				mv "$csv_to_move" "data/processed/"
			done
		fi
		
	fi
fi
