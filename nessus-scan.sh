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
echo "Attente de l'initialisation des conteneurs (60 secondes)..."
sleep 60

# Récupération des adresses IP des conteneurs
NESSUS_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $NESSUS_CONTAINER_NAME)

# Vérification de l'accès à Nessus
echo "Vérification de l'accès à Nessus..."
if ! curl -k -s "https://$NESSUS_IP:8834" >/dev/null; then
  echo "Impossible de se connecter à Nessus sur $NESSUS_IP:8834. Assurez-vous que le conteneur est actif."
  exit 1
fi

# Création d'un compte Nessus Essentials
echo "Création d'un compte Nessus Essentials..."
CREATE_ACCOUNT_RESPONSE=$(curl -s -k -X POST -H "Content-Type: application/json" -d '{
  "username": "'"$USERNAME"'",
  "password": "'"$PASSWORD"'",
  "permissions": 128,
  "type": "local"
}' "https://$NESSUS_IP:8834/users")
echo "Réponse de création de compte : $CREATE_ACCOUNT_RESPONSE"

# Authentification à Nessus
echo "Tentative d'authentification à Nessus..."
TOKEN=$(curl -s -k -X POST -d "username=$USERNAME&password=$PASSWORD" "https://$NESSUS_IP:8834/session" | jq -r .token)

if [ -z "$TOKEN" ]; then
  echo "Erreur d'authentification. Vérifiez vos identifiants."
  exit 1
fi

echo "Authentification réussie. Token récupéré : $TOKEN"
