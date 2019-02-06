#!/bin/bash

set -e
set -u

# The variables have defaults that can be set from outside, e.g. via -e "DB_HOST=mydbms" or from the docker-compose.yml file.
# Also see https://docs.docker.com/engine/reference/builder/#environment-replacement

# postgres
db_host=${DB_HOST:-db}
db_port=${DB_PORT:-5432}
db_name=${DB_NAME:-metasfresh}
db_user=${DB_USER:-metasfresh}
db_password=${DB_PASSWORD:-$(echo $secret_db_password)}
db_connection_pool_max_size=${DB_CONNECTION_POOL_MAX_SIZE:-UNSET}

# elastic search
es_host=${ES_HOST:-search}
es_port=${ES_PORT:-9300}

# metasfresh-admin
admin_url=${METASFRESH_ADMIN_URL:-NONE}

# self
app_host=${APP_HOST:-app}

echo_variable_values()
{
 echo "Note: all these variables can be set from outside."
 echo ""
 echo "DB_HOST=${db_host}"
 echo "DB_PORT=${db_port}"
 echo "DB_NAME=${db_name}"
 echo "DB_USER=${db_user}"
 echo "DB_PASSWORD=*******"
 echo "DB_CONNECTION_POOL_MAX_SIZE=${db_connection_pool_max_size}"
 echo "ES_HOST=${es_host}"
 echo "ES_PORT=${es_port}"
 echo "METASFRESH_ADMIN_URL=${admin_url}"
 echo "APP_HOST=${app_host}"
}

set_properties()
{
 local prop_file="$1"
 if [[ $(cat $prop_file | grep FOO | wc -l) -ge "1" ]]; then
	sed -Ei "s/FOO_DBMS/${db_host}/g" $prop_file
	sed -Ei "s/FOO_DBMS_PORT/${db_port}/g" $prop_file
	sed -Ei "s/FOO_DB_NAME/${db_name}/g" $prop_file
	sed -Ei "s/FOO_DB_USER/${db_user}/g" $prop_file
	sed -Ei "s/FOO_DB_PASSWORD/${db_password}/g" $prop_file
	sed -Ei "s/FOO_APP/${app_host}/g" $prop_file
 fi
}

run_metasfresh()
{
 if [ "$db_connection_pool_max_size" != "UNSET" ];
 then
 	metasfresh_db_connectionpool_params="-Dc3p0.maxPoolSize=${db_connection_pool_max_size}"
 else 
	metasfresh_db_connectionpool_params=""
 fi

 if [ "$admin_url" != "NONE" ]; 
 then
	# see https://codecentric.github.io/spring-boot-admin/1.5.0/#spring-boot-admin-client
	# spring.boot.admin.client.prefer-ip=true because within docker, the hostname is no help
	metasfresh_admin_params="-Dspring.boot.admin.url=${admin_url} -Dmanagement.security.enabled=false -Dspring.boot.admin.client.prefer-ip=true"
 else
	metasfresh_admin_params=""
 fi

 # thx to https://blog.csanchez.org/2017/05/31/running-a-jvm-in-a-container-without-getting-killed/
 local MEMORY_PARAMS="-XX:+UnlockExperimentalVMOptions -XX:+UseCGroupMemoryLimitForHeap -XX:MaxRAMFraction=1"

 local es_params="-Dspring.data.elasticsearch.cluster-nodes=${es_host}:${es_port}"

 cd /opt/metasfresh/ \
 && java \
 -Dsun.misc.URLClassPath.disableJarChecking=true \
 ${MEMORY_PARAMS} \
 -XX:+HeapDumpOnOutOfMemoryError \
 ${es_params} \
 ${metasfresh_db_connectionpool_params} \
 ${metasfresh_admin_params} \
 -DPropertyFile=/opt/metasfresh/metasfresh.properties \
 -agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=8788 \
 -jar metasfresh-app.jar
}

echo_variable_values

set_properties /opt/metasfresh/metasfresh.properties
set_properties /opt/metasfresh/local_settings.properties
set_properties /root/local_settings.properties

run_metasfresh

exit 0
