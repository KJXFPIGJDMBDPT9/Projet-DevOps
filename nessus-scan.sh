#!/bin/bash
docker network create akaunting_network
docker run -d --name akaunting --network akaunting_network akaunting/akaunting
docker run -d --name mysql --network akaunting_network -e MYSQL_ROOT_PASSWORD=root_password mysql:8.0
docker run -d --name nessus --network akaunting_network tenableofficial/nessus
sleep 30
NESSUS_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' nessus)
TARGET_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' akaunting)
USERNAME="nourelhoda"
PASSWORD="nourelhoda"
TOKEN=$(curl -k -s -X POST -d "username=$USERNAME&password=$PASSWORD" "https://$NESSUS_IP:8834/session" | jq -r .token)
if [ -z "$TOKEN" ]; then
  echo "Erreur d'authentification"
  exit 1
fi
POLICY_LIST=$(curl -s -X GET -H "X-Cookie: token=$TOKEN" "https://$NESSUS_IP:8834/policies")
POLICY_UUID=$(echo $POLICY_LIST | jq -r '.policies[] | select(.name | test("Web Application Tests")) | .uuid')
if [ -z "$POLICY_UUID" ]; then
  echo "Politique Web Application Tests non trouvée"
  exit 1
fi
echo "Politique Web Application Tests trouvée avec UUID : $POLICY_UUID"
SCAN_RESPONSE=$(curl -s -X POST -H "X-Cookie: token=$TOKEN" -d '{"uuid":"'$POLICY_UUID'"}' "https://$NESSUS_IP:8834/scans")
SCAN_ID=$(echo $SCAN_RESPONSE | jq -r '.scan.id')
if [ -z "$SCAN_ID" ]; then
  echo "Erreur de lancement du scan"
  exit 1
fi
echo "Scan lancé avec succès, Scan ID : $SCAN_ID"
while true; do
  SCAN_STATUS=$(curl -s -X GET -H "X-Cookie: token=$TOKEN" "https://$NESSUS_IP:8834/scans/$SCAN_ID" | jq -r '.scan.status')
  if [ "$SCAN_STATUS" == "completed" ]; then
    echo "Le scan est terminé"
    break
  else
    echo "Le scan est en cours... Attente de 30 secondes"
    sleep 30
  fi
done
echo "Récupération du rapport du scan"
curl -s -X GET -H "X-Cookie: token=$TOKEN" "https://$NESSUS_IP:8834/scans/$SCAN_ID/report" -o "scan_report.html"
echo "Le rapport du scan est sauvegardé dans scan_report.html"
