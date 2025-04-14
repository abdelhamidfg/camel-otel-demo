#!/bin/bash

wait_for_operator_csv() {
  local NAMESPACE="$1"
  local CSV_PREFIX="$2"
  local TIMEOUT=180
  local INTERVAL=5
  local ELAPSED=0

  echo "⏳ Waiting for CSV starting with '$CSV_PREFIX' in namespace '$NAMESPACE' to reach 'Succeeded' status..."

  while [ $ELAPSED -lt $TIMEOUT ]; do
    #CSV_NAME=$(oc get csv -n "$NAMESPACE" -o jsonpath="{.items[?(@.metadata.name.startsWith('$CSV_PREFIX'))].metadata.name}" 2>/dev/null)
    CSV_NAME=$(oc get csv -n "$NAMESPACE" -o name | grep "$CSV_PREFIX" | head -n 1 | cut -d/ -f2)
    echo $CSV_NAME
    if [ -n "$CSV_NAME" ]; then
      PHASE=$(oc get csv "$CSV_NAME" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
      echo "🔍 Found CSV: $CSV_NAME — Phase: $PHASE"

      if [ "$PHASE" == "Succeeded" ]; then
        echo "✅ Operator CSV '$CSV_NAME' has successfully installed."
        return 0
      fi
    else
      echo "📭 Waiting for CSV with prefix '$CSV_PREFIX' to appear in '$NAMESPACE'..."
    fi

    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
  done

  echo "❌ Timeout: CSV starting with '$CSV_PREFIX' not in 'Succeeded' state within $TIMEOUT seconds."
  return 1
}

enable_uwm(){
echo enable User Workload Monitoring UWM in OpenShift
oc apply -f ${BASEDIR}/uwm.yaml

}

install_minio() {
echo install MinIO
oc apply -f ${BASEDIR}/minio/minio.yaml
oc apply -f ${BASEDIR}/minio/minio-service.yaml
oc apply -f ${BASEDIR}/minio/minio-route.yaml

echo wait for minio deployment ready
oc wait --timeout=90s --for=condition=Available=True deployment/minio

echo creating buckets
export MINIO_POD=$(oc get pod -l app=minio  -o go-template --template '{{range .items}}{{.metadata.name}}{{"\n"}}{{end}}')
oc rsh $MINIO_POD mc mb /data/tempostack
oc rsh $MINIO_POD mc mb /data/lokistack

}
install_hawtio(){

envsubst <  ${BASEDIR}/hawtio/operator-group.yaml | oc apply -f -
envsubst <  ${BASEDIR}/hawtio/hawtio-operator-subscription.yaml | oc apply -f -
wait_for_operator_csv "${PROJECT}" "red-hat-hawtio-operator"
envsubst <  ${BASEDIR}/hawtio/hawtio.yaml | oc apply -f - 

}
install_database(){
echo creating database instance
oc create secret generic postgres-secret --from-env-file=${BASEDIR}/db/postgres-secret && oc label secret postgres-secret "app=postgres"
oc apply -f ${BASEDIR}/db/postgres-pvc.yaml
oc apply -f ${BASEDIR}/db/postgres-deployment.yaml
oc apply -f ${BASEDIR}/db/postgres-service.yaml

echo wait for postgres deployment ready
oc wait --timeout=90s --for=condition=Available=True deployment/postgres


PSTG_POD=$(oc get pod -n $PROJECT -l app=postgres -o jsonpath='{.items[0].metadata.name}')
echo creating tables and data
PGPASSWORD=admin oc exec -i -n "$PROJECT" "$PSTG_POD" -- bash -c 'PGPASSWORD=admin psql -U admin -d flightsdb' < "${BASEDIR}/db/data.sql"
}

install_logging(){
echo install Loki operator
read -p "Enter your storageClassName: " storageClassName
export storageClassName=${storageClassName}
echo storageClassName=${storageClassName}
#operator need to be installed in this ns
oc create namespace openshift-operators-redhat --dry-run=client -o yaml | oc apply -f -
#lokistack need to be installed in this ns to be contacted by Log UI Plugin
oc create namespace openshift-logging --dry-run=client -o yaml | oc apply -f -
 #oc project ${PROJECT}

oc create secret generic minio-secret-lokistack \
	--from-literal=access_key_id=minio --from-literal=access_key_secret=minio123 \
	--from-literal=endpoint=http://minio.${PROJECT}.svc.cluster.local:9000/ --from-literal=bucketnames=lokistack -n openshift-logging

oc apply -f ${BASEDIR}/loki/loki-operator-group.yaml
oc apply -f ${BASEDIR}/loki/loki-operator-subscription.yaml

wait_for_operator_csv "openshift-operators-redhat" "loki-operator"
echo install LokiStack
#oc apply -f ${BASEDIR}/loki/loki-stack.yaml -n openshift-logging
envsubst <   ${BASEDIR}/loki/loki-stack.yaml | oc apply -n openshift-logging -f -

echo wait for Loki Stack to be installed
#!/bin/bash

# Name and namespace of your LokiStack CR
LOKISTACK_NAME="logging-loki"
NAMESPACE="openshift-logging"  # change this if your LokiStack is in a different namespace

# Maximum wait time and interval (in seconds)
MAX_WAIT=300
SLEEP_INTERVAL=10

echo "Checking status of LokiStack CR: $LOKISTACK_NAME in namespace: $NAMESPACE"

elapsed=0
ready=false

while [ $elapsed -lt $MAX_WAIT ]; do
    condition=$(oc get lokistack "$LOKISTACK_NAME" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)

    if [ "$condition" == "True" ]; then
        echo "✅ LokiStack CR '$LOKISTACK_NAME' is Ready."
        ready=true
        break
    else
        echo "⏳ LokiStack is not ready yet... waiting $SLEEP_INTERVAL seconds"
        sleep $SLEEP_INTERVAL
        elapsed=$((elapsed + SLEEP_INTERVAL))
    fi
done

if [ "$ready" != "true" ]; then
    echo "❌ Timeout reached. LokiStack CR '$LOKISTACK_NAME' did not become Ready within $MAX_WAIT seconds."
    # Optionally set a warning flag or handle the error gracefully
fi

echo install Red Hat OpenShift Logging Operator

oc apply -f ${BASEDIR}/loki/logging-operator-group.yaml
oc apply -f ${BASEDIR}/loki/openshift-logging-operator-subscription.yaml
wait_for_operator_csv "openshift-logging" "cluster-logging"


oc create serviceaccount collector -n openshift-logging
# Wait for the ServiceAccount to be created
until oc get serviceaccount collector -n openshift-logging >/dev/null 2>&1; do
  echo "Waiting for ServiceAccount 'collector' to be created..."
  sleep 1
done
# Allow the collector's service account to write data to the LokiStack CR:
oc adm policy add-cluster-role-to-user logging-collector-logs-writer -z collector -n openshift-logging

# Allow the collector's service account to collect logs:
oc adm policy add-cluster-role-to-user collect-application-logs -z collector -n openshift-logging
oc adm policy add-cluster-role-to-user collect-audit-logs -z collector -nopenshift-logging
oc adm policy add-cluster-role-to-user collect-infrastructure-logs -z collector -n openshift-logging
echo Creating clusterLogForwarder
oc apply -f ${BASEDIR}/loki/clusterLogForwarder.yaml
 
}

install_tempo(){
    oc create secret generic minio-secret-tempostack \
	--from-literal=access_key_id=minio --from-literal=access_key_secret=minio123 \
	--from-literal=endpoint=http://minio.${PROJECT}.svc.cluster.local:9000/ --from-literal=bucket=tempostack
echo install tempostack operator
oc apply -f ${BASEDIR}/tempo/tempo-operator-project.yaml
oc apply -f ${BASEDIR}/tempo/tempo-operator-group.yaml
oc apply -f ${BASEDIR}/tempo/tempo-operator-subscription.yaml

echo wait for tempostack operator to be installed
sleep 1m
oc wait --timeout=90s --for=condition=Available=True deployment/tempo-operator-controller -n openshift-tempo-operator

echo creating tempostack
oc apply -f ${BASEDIR}/tempo/tempo-stack.yaml

TEMPOSTACK_NAME="otel"
# Maximum wait time and interval (in seconds)
MAX_WAIT=300
SLEEP_INTERVAL=10
echo "Checking status of TempoStack CR: $TEMPOSTACK_NAME in namespace: ${PROJECT}"

elapsed=0
while [ $elapsed -lt $MAX_WAIT ]; do
    condition=$(oc get tempostack "$TEMPOSTACK_NAME" -n "$PROJECT" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)

    if [ "$condition" == "True" ]; then
        echo "✅ TempoStack CR '$TEMPOSTACK_NAME' is Ready."
        break
    else
        echo "⏳ TempoStack is not ready yet... waiting $SLEEP_INTERVAL seconds"
        sleep $SLEEP_INTERVAL
        elapsed=$((elapsed + SLEEP_INTERVAL))
    fi
done

if [ "$condition" != "True" ]; then
    echo "❌ Timeout reached. TempoStack CR '$TEMPOSTACK_NAME' did not become Ready within $MAX_WAIT seconds."
    exit 1
fi


}

install_otel(){
echo install opentelemetry operator

 

oc apply -f ${BASEDIR}/otel/otel-operator-project.yaml
oc apply -f ${BASEDIR}/otel/otel-operator-group.yaml
oc apply -f ${BASEDIR}/otel/otel-operator-subscription.yaml

echo wait for opentelemetry operator to be installed
sleep 1m
oc wait --timeout=90s --for=condition=Available=True deployment/opentelemetry-operator-controller-manager -n openshift-opentelemetry-operator

echo install cluster observability operator
oc apply -f ${BASEDIR}/observability/co-operator-subscription.yaml

echo wait for cluster observability operator to be installed
sleep 1m
oc wait --timeout=90s --for=condition=Available=True deployment/observability-operator -n openshift-operators

#install Observe -> Logs menu
oc apply -f ${BASEDIR}/observability/logging-ui-plugin.yaml


echo creating opentelemetry collector instance
envsubst <  ${BASEDIR}/otel/otel-collector.yaml | oc apply -f -
echo creating opentelemetry instrumentation
envsubst <   ${BASEDIR}/otel/otel-instrumentation.yaml | oc apply -f -
}

install_dashboard(){
echo installing Grafana
oc apply -f ${BASEDIR}/dashboard/grafana-subscription.yaml

wait_for_operator_csv "openshift-operators" "grafana-operator" #grafana-operator.v5.17.1
export WILDCARD_DOMAIN=$(oc get ingress.config.openshift.io cluster -o jsonpath='{.spec.domain}')
echo "✅ Wildcard domain is: $WILDCARD_DOMAIN"

envsubst <  ${BASEDIR}/dashboard/grafana.yaml | oc apply -f -

oc create sa grafana-oauth-sa  -n ${PROJECT}
export ACCESS_TOKEN=$(oc create token grafana-oauth-sa --duration=$((365*24))h)
envsubst <  ${BASEDIR}/dashboard/grafanaDatasource.yaml | oc apply -f -

oc apply -f ${BASEDIR}/dashboard/camel-integration-micrometermetrics_grafanadashboard.yaml
oc apply -f ${BASEDIR}/dashboard/camel-route-micrometermetrics_grafanadashboard.yaml

}


deploy_app(){
    envsubst <  ${BASEDIR}/service.yaml | oc apply -f -
    mvn -f ${BASEDIR}/flight-information-service/pom.xml clean package -Dquarkus.kubernetes.deploy=true
    mvn -f ${BASEDIR}/booking-service/pom.xml clean package -Dquarkus.kubernetes.deploy=true

 
}
######################################################################################################################
BASEDIR=$(dirname "$SCRIPT")
echo  ${BASEDIR}
read -p "Enter project name [rh-demo]: " PROJECT
PROJECT=${PROJECT:-rh-demo}
echo "Using project: $PROJECT"
#storageClassName=ocs-external-storagecluster-ceph-rbd

export PROJECT=${PROJECT}
echo creating namespace ${PROJECT}
oc create namespace  ${PROJECT} --dry-run=client -o yaml | oc apply -f -
oc project ${PROJECT}

echo -e "Choose an option:\n0) Enable User Workload Monitoring\n1) Install Minio\n2) Install Database\n3) Install Logging\n4) Install Tempo\n5) Install otel \n6) Install Dashboard\n7) Deploy Applicationsn\n8) Install Hawtio \nall) Run all parts (default)"
read -p "Enter your choice [all]: " choice

# If user presses Enter, use "all" as the default
choice=${choice:-all}

echo "You selected: $choice"
case $choice in
  0)
    echo "enable_uwm..."
    enable_uwm
    ;;
  1)
    echo "install_minio..."
    install_minio
    ;;
  2)
    echo "install_database..."
    install_database
    ;;
  3)
    echo "install_logging..."
    install_logging
    ;;
  4)
    echo "install_tempo.."
    install_tempo
    ;;
  5)
    echo "install_otel..."
    install_otel

    ;;    
  6)
    echo "install_dashboard..."
    install_dashboard

    ;;
  7)
    echo "Deploying app..."
    deploy_app

    ;;
  8)
    echo "install_hawtio..."
    install_hawtio

    ;;         
         
  all)
    echo "Running All Parts..."
    enable_uwm
    install_minio
    install_database
    install_logging
    install_tempo
    install_otel
    install_dashboard
    install_hawtio
    deploy_app
    ;;
  *)
    echo "Invalid input"
    exit 1
    ;;
esac