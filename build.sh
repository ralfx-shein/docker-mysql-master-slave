#!/bin/bash -ex
PS4='${LINENO}:'

docker-compose down -v
sudo rm -rf ./model/data/*
for N in 1 2; do
    sudo rm -rf ./replica/data$N/*
done
sleep 5
docker-compose build
docker-compose up -d
sleep 30
until docker exec percona_model sh -c 'export MYSQL_PWD=111; mysql -u root -e "show master status\G;"'
do
    echo "Waiting for percona_model database connection..."
    sleep 5
done

priv_stmt='CREATE USER "mydb_replica_user"@"%" IDENTIFIED WITH mysql_native_password BY "mydb_replica_pwd"; GRANT REPLICATION replica ON *.* TO "mydb_replica_user"@"%"; FLUSH PRIVILEGES;'
docker exec percona_model sh -c "export MYSQL_PWD=111; mysql -u root -e '$priv_stmt'"

# sleep 45
#replica
for N in 1 2; do
    until docker-compose exec percona_replica$N sh -c 'export MYSQL_PWD=111; mysql -u root -e "show replica status \G;"'
    do
        echo "Waiting for percona_replica$N database connection..."
        sleep 5
    done

    MS_STATUS=`docker exec percona_model sh -c 'export MYSQL_PWD=111; mysql -u root -e "SHOW model STATUS"'`
    CURRENT_LOG=`echo $MS_STATUS | awk '{print $6}'`
    CURRENT_POS=`echo $MS_STATUS | awk '{print $7}'`

    start_replica_stmt="CHANGE REPLICATION SOURCE to SOURCE_HOST='percona_model',SOURCE_USER='mydb_replica_user',SOURCE_PASSWORD='mydb_replica_pwd', SOURCE_LOG_FILE='$CURRENT_LOG',SOURCE_LOG_POS=$CURRENT_POS; START REPLICA;"
    start_replica_cmd='export MYSQL_PWD=111; mysql -u root -e "'
    start_replica_cmd+="$start_replica_stmt"
    start_replica_cmd+='"'
    docker exec percona_replica$N sh -c "$start_replica_cmd"
    echo "Replication status on percona_replica$N "
    docker exec percona_replica$N sh -c "export MYSQL_PWD=111; mysql -u root -e 'SHOW REPLICA STATUS \G'"
done