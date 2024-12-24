#!/bin/bash

# Variables
NETWORK_NAME="akaunting_network"
MYSQL_CONTAINER_NAME="mysql"
NESSUS_CONTAINER_NAME="nessus"
AKAUNTING_CONTAINER_NAME="akaunting"
MYSQL_ROOT_PASSWORD="root_password"
USERNAME="nourelhoda"
PASSWORD="nourelhoda"

# Création du réseau Docker
echo "Création du réseau Docker..."
docker network create $NETWORK_NAME

# Lancement des conteneurs Docker
echo "Lancement des conteneurs Docker..."
docker run -d --name $AKAUNTING_CONTAINER_NAME --network $NETWORK_NAME akaunting/akaunting
docker run -d --name $MYSQL_CONTAINER_NAME --network $NETWORK_NAME -e MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD mysql:8.0
docker run -d --name $NESSUS_CONTAINER_NAME --network $NETWORK_NAME tenableofficial/nessus

# Attente de l'initialisation des conteneurs
echo "Attente de l'initialisation des conteneurs (30 secondes)..."
sleep 30

# Récupération des adresses IP des conteneurs
NESSUS_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $NESSUS_CONTAINER_NAME)
TARGET_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $AKAUNTING_CONTAINER_NAME)

# Vérification de l'accès à Nessus avec limite de tentatives
echo "Vérification de l'accès à Nessus..."
MAX_RETRIES=30
RETRIES=0
NESSUS_READY=false

while [ $RETRIES -lt $MAX_RETRIES ]; do
  if curl -k -s "https://$NESSUS_IP:8834" >/dev/null; then
    NESSUS_READY=true
    break
  fi
  echo "Nessus n'est pas prêt. Réessai dans 10 secondes... ($RETRIES/$MAX_RETRIES)"
  sleep 10
  RETRIES=$((RETRIES + 1))
done

if [ "$NESSUS_READY" = false ]; then
  echo "Nessus n'a pas pu démarrer après $MAX_RETRIES tentatives. Vérifiez les journaux du conteneur."
  docker logs $NESSUS_CONTAINER_NAME
  exit 1
fi

# Création d'un compte Nessus Essentials
echo "Création d'un compte Nessus Essentials..."
curl -s -k -X POST -H "Content-Type: application/json" -d '{
  "username": "'"$USERNAME"'",
  "password": "'"$PASSWORD"'",
  "permissions": 128,
  "type": "local"
}' "https://$NESSUS_IP:8834/users" >/dev/null

# Authentification à Nessus
echo "Tentative d'authentification à Nessus..."
TOKEN=$(curl -s -k -X POST -d "username=$USERNAME&password=$PASSWORD" "https://$NESSUS_IP:8834/session" | jq -r .token)

if [ -z "$TOKEN" ]; then
  echo "Erreur d'authentification. Vérifiez vos identifiants."
  exit 1
fi
echo "Authentification réussie. Token récupéré."

# Récupération de la liste des politiques disponibles
echo "Récupération de la liste des politiques disponibles..."
POLICY_LIST=$(curl -s -k -X GET -H "X-Cookie: token=$TOKEN" "https://$NESSUS_IP:8834/policies")
POLICY_UUID=$(echo $POLICY_LIST | jq -r '.policies[] | select(.name == "Web Application Tests") | .uuid')

if [ -z "$POLICY_UUID" ]; then
  echo "Politique Web Application Tests non trouvée. Vérifiez les politiques disponibles."
  exit 1
fi
echo "Politique Web Application Tests trouvée avec UUID : $POLICY_UUID"

# Lancement du scan
echo "Lancement du scan..."
SCAN_RESPONSE=$(curl -s -k -X POST -H "X-Cookie: token=$TOKEN" -d '{"uuid":"'$POLICY_UUID'", "settings":{"name":"Akaunting Scan", "text_targets":"'$TARGET_IP'"}}' "https://$NESSUS_IP:8834/scans")
SCAN_ID=$(echo $SCAN_RESPONSE | jq -r '.scan.id')

if [ -z "$SCAN_ID" ]; then
  echo "Erreur de lancement du scan."
  exit 1
fi
echo "Scan lancé avec succès. Scan ID : $SCAN_ID"

# Vérification du statut du scan
while true; do
  SCAN_STATUS=$(curl -s -k -X GET -H "X-Cookie: token=$TOKEN" "https://$NESSUS_IP:8834/scans/$SCAN_ID" | jq -r '.info.status')
  if [ "$SCAN_STATUS" == "completed" ]; then
    echo "Le scan est terminé."
    break
  else
    echo "Scan en cours... Attente de 30 secondes."
    sleep 30
  fi
done

# Récupération du rapport du scan
echo "Récupération du rapport du scan..."
curl -s -k -X GET -H "X-Cookie: token=$TOKEN" "https://$NESSUS_IP:8834/scans/$SCAN_ID/export" -o "scan_report.html"
echo "Le rapport du scan est sauvegardé dans 'scan_report.html'."

# Suppression du token de session
echo "Suppression du token de session..."
curl -k -X DELETE -H "X-Cookie: token=$TOKEN" "https://$NESSUS_IP:8834/session"

# Nettoyage des conteneurs Docker
echo "Nettoyage des conteneurs Docker..."
docker stop $AKAUNTING_CONTAINER_NAME $MYSQL_CONTAINER_NAME $NESSUS_CONTAINER_NAME
docker rm $AKAUNTING_CONTAINER_NAME $MYSQL_CONTAINER_NAME $NESSUS_CONTAINER_NAME
docker network rm $NETWORK_NAME

echo "Script terminé avec succès."
