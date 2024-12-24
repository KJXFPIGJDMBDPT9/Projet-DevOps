#!/bin/bash
NETWORK_NAME="akaunting_network"
MYSQL_CONTAINER_NAME="mysql"
NESSUS_CONTAINER_NAME="nessus"
AKAUNTING_CONTAINER_NAME="akaunting"
MYSQL_ROOT_PASSWORD="root_password"
USERNAME="nourelhoda"
PASSWORD="nourelhoda"
EMAIL="nourelhoda@example.com"
echo "Création du réseau Docker..."
docker network create $NETWORK_NAME
echo "Lancement des conteneurs Docker..."
docker run -d --name $AKAUNTING_CONTAINER_NAME --network $NETWORK_NAME akaunting/akaunting
docker run -d --name $MYSQL_CONTAINER_NAME --network $NETWORK_NAME -e MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD mysql:8.0
docker run -d --name $NESSUS_CONTAINER_NAME --network $NETWORK_NAME tenableofficial/nessus
echo "Attente de l'initialisation des conteneurs (30 secondes)..."
sleep 30
NESSUS_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $NESSUS_CONTAINER_NAME)
TARGET_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $AKAUNTING_CONTAINER_NAME)
echo "Vérification de l'accès à Nessus..."
if ! curl -k -s "https://$NESSUS_IP:8834" >/dev/null; then
  echo "Impossible de se connecter à Nessus sur $NESSUS_IP:8834. Assurez-vous que le conteneur est actif."
  exit 1
fi
echo "Création d'un compte Nessus Essentials..."
CREATE_ACCOUNT_RESPONSE=$(curl -s -k -X POST -H "Content-Type: application/json" -d '{
  "username": "'$USERNAME'",
  "password": "'$PASSWORD'",
  "email": "'$EMAIL'"
}' "https://$NESSUS_IP:8834/users")
if ! echo $CREATE_ACCOUNT_RESPONSE | jq -e '.error' >/dev/null 2>&1; then
  echo "Compte Nessus Essentials créé avec succès."
else
  echo "Erreur lors de la création du compte Nessus Essentials : $(echo $CREATE_ACCOUNT_RESPONSE | jq -r '.error')"
  exit 1
fi
echo "Tentative d'authentification à Nessus..."
TOKEN=$(curl -s -k -X POST -d "username=$USERNAME&password=$PASSWORD" "https://$NESSUS_IP:8834/session" | jq -r .token)
if [ -z "$TOKEN" ]; then
  echo "Erreur d'authentification. Vérifiez vos identifiants."
  exit 1
fi
echo "Authentification réussie. Token récupéré."
echo "Récupération de la liste des politiques disponibles..."
POLICY_LIST=$(curl -s -k -X GET -H "X-Cookie: token=$TOKEN" "https://$NESSUS_IP:8834/policies")
echo "Liste des politiques :"
echo $POLICY_LIST
POLICY_UUID=$(echo $POLICY_LIST | jq -r '.policies[] | select(.name == "Web Application Tests") | .uuid')
if [ -z "$POLICY_UUID" ]; then
  echo "Politique Web Application Tests non trouvée. Vérifiez les politiques disponibles dans Nessus."
  exit 1
fi
echo "Politique Web Application Tests trouvée avec UUID : $POLICY_UUID"
echo "Lancement du scan..."
SCAN_RESPONSE=$(curl -s -k -X POST -H "X-Cookie: token=$TOKEN" -d '{"uuid":"'$POLICY_UUID'", "settings":{"name":"Akaunting Scan", "text_targets":"'$TARGET_IP'"}}' "https://$NESSUS_IP:8834/scans")
SCAN_ID=$(echo $SCAN_RESPONSE | jq -r '.scan.id')
if [ -z "$SCAN_ID" ]; then
  echo "Erreur de lancement du scan. Vérifiez les paramètres de la politique et la cible."
  exit 1
fi
echo "Scan lancé avec succès. Scan ID : $SCAN_ID"
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
echo "Récupération du rapport du scan..."
curl -s -k -X GET -H "X-Cookie: token=$TOKEN" "https://$NESSUS_IP:8834/scans/$SCAN_ID/export" -o "scan_report.html"
echo "Le rapport du scan est sauvegardé dans 'scan_report.html'."

echo "Suppression du token de session pour des raisons de sécurité..."
curl -k -X DELETE -H "X-Cookie: token=$TOKEN" "https://$NESSUS_IP:8834/session"
echo "Nettoyage des conteneurs Docker..."
docker stop $AKAUNTING_CONTAINER_NAME $MYSQL_CONTAINER_NAME $NESSUS_CONTAINER_NAME
docker rm $AKAUNTING_CONTAINER_NAME $MYSQL_CONTAINER_NAME $NESSUS_CONTAINER_NAME
docker network rm $NETWORK_NAME
echo "Script terminé avec succès."
