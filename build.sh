#!/bin/bash -ex
docker-compose down -v
sudo rm -rf ./master/data/*
for N in 1 2; do
    sudo rm -rf ./slave/data$N/*
done
sleep 5
docker-compose build
docker-compose up -d
sleep 30
until docker exec mysql_master sh -c 'export MYSQL_PWD=111; mysql -u root -e "show master status \G;"'
do
    echo "Waiting for mysql_master database connection..."
    sleep 5
done

priv_stmt='CREATE USER "mydb_slave_user"@"%" IDENTIFIED WITH mysql_native_password BY "mydb_slave_pwd"; GRANT REPLICATION SLAVE ON *.* TO "mydb_slave_user"@"%"; FLUSH PRIVILEGES;'
docker exec mysql_master sh -c "export MYSQL_PWD=111; mysql -u root -e '$priv_stmt'"

# sleep 45
#replica
for N in 1 2; do
    until docker-compose exec mysql_slave$N sh -c 'export MYSQL_PWD=111; mysql -u root -e "show replica status \G;"'
    do
        echo "Waiting for mysql_slave$N database connection..."
        sleep 5
    done

    MS_STATUS=`docker exec mysql_master sh -c 'export MYSQL_PWD=111; mysql -u root -e "SHOW MASTER STATUS"'`
    CURRENT_LOG=`echo $MS_STATUS | awk '{print $6}'`
    CURRENT_POS=`echo $MS_STATUS | awk '{print $7}'`

    start_replica_stmt="CHANGE REPLICATION SOURCE to SOURCE_HOST='mysql_master',SOURCE_USER='mydb_slave_user',SOURCE_PASSWORD='mydb_slave_pwd', SOURCE_LOG_FILE='$CURRENT_LOG',SOURCE_LOG_POS=$CURRENT_POS; START REPLICA;"
    start_replica_cmd='export MYSQL_PWD=111; mysql -u root -e "'
    start_replica_cmd+="$start_replica_stmt"
    start_replica_cmd+='"'
    docker exec mysql_slave$N sh -c "$start_replica_cmd"
    echo "Replication status on mysql_slave$N "
    docker exec mysql_slave$N sh -c "export MYSQL_PWD=111; mysql -u root -e 'SHOW REPLICA STATUS \G'"
done