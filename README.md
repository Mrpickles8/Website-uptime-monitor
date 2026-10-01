# aws-uptime-monitor
 
> 🌍 **Select your language / Choisissez votre langue / Sprache wählen**
 
[🇫🇷 Français](#français) ·
[🇬🇧 English](#english) ·
[🇩🇪 Deutsch](#deutsch)
 
---
 
## Français
 
## Objectif
 
Ce projet déploie un système de monitoring de disponibilité entièrement serverless sur AWS. Une fonction Lambda se déclenche automatiquement toutes les 5 minutes via EventBridge et vérifie chaque site surveillé sur trois critères : accessibilité, temps de réponse et code HTTP. En cas d'anomalie, une alerte email est envoyée immédiatement via SNS. Chaque résultat est stocké dans DynamoDB avec un TTL de 30 jours.
 
## Problème résolu
 
Un site en panne coûte des clients, du chiffre d'affaires et de la réputation. Sans monitoring automatique, la panne est souvent découverte par un client avant par l'équipe technique. Ce projet détecte les pannes en moins de 5 minutes et alerte instantanément.
 
## Compétences acquises
 
- Déploiement de fonctions Lambda serverless avec Terraform
- Automatisation de tâches planifiées avec EventBridge
- Stockage de séries temporelles dans DynamoDB avec TTL automatique
- Notification d'alertes en temps réel via SNS
- Principe du moindre privilège appliqué aux rôles IAM Lambda
- Pipeline CI/CD avec GitHub Actions
## Outils utilisés
 
- Terraform (Infrastructure as Code)
- AWS : Lambda · DynamoDB · SNS · EventBridge · IAM · CloudWatch
- Python 3.12
## Architecture
 
```
EventBridge (rate: 5 minutes)
    → Lambda (lambda_monitor.py)
        → urllib : vérifie accessibilité + temps de réponse + code HTTP
            → DynamoDB : stocke chaque résultat (TTL 30 jours)
            → SNS → Email d'alerte si status != OK
```
 
## Ce que la Lambda vérifie
 
Pour chaque site surveillé, trois vérifications :
 
| Vérification | Condition d'alerte | Status |
|---|---|---|
| Accessibilité | Exception urllib (timeout, DNS, connexion) | `DOWN` |
| Code HTTP | Code != 200 | `ERROR` |
| Temps de réponse | Dépasse le seuil défini (défaut 3000ms) | `SLOW` |
 
## Étapes
 
### Ref 1 : Variables
 
```hcl
variable "aws_region" { default = "eu-west-1" }
variable "project_name" { default = "uptime-monitor" }
variable "alert_email" { default = "davidartaud1@gmail.com" }
 
variable "websites_to_monitor" {
  type    = list(string)
  default = [
    "https://www.google.com",
    "https://github.com",
    "https://aws.amazon.com"
  ]
}
 
variable "response_time_threshold_ms" {
  type    = number
  default = 3000
}
```
 
### Ref 2 : DynamoDB — stockage des résultats
 
La table DynamoDB utilise `PAY_PER_REQUEST` — aucune capacité à provisionner. La clé composite `website_url + timestamp` permet de stocker et requêter l'historique par site. Le TTL supprime automatiquement les entrées après 30 jours.
 
```hcl
resource "aws_dynamodb_table" "uptime_results" {
  name         = "${var.project_name}-results"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "website_url"
  range_key    = "timestamp"
 
  attribute { name = "website_url" type = "S" }
  attribute { name = "timestamp"   type = "S" }
 
  ttl {
    attribute_name = "ttl"
    enabled        = true
  }
}
```
 
### Ref 3 : SNS — alertes email
 
```hcl
resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"
}
 
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}
```
 
### Ref 4 : IAM Role — least privilege
 
La Lambda n'a que les permissions strictement nécessaires : écrire dans DynamoDB, publier dans SNS, et écrire ses logs CloudWatch.
 
```hcl
resource "aws_iam_role_policy" "lambda" {
  role = aws_iam_role.lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow" Action = ["dynamodb:PutItem","dynamodb:GetItem"]
        Resource = [aws_dynamodb_table.uptime_results.arn] },
      { Effect = "Allow" Action = ["sns:Publish"]
        Resource = [aws_sns_topic.alerts.arn] },
      { Effect = "Allow" Action = ["logs:*"] Resource = ["*"] }
    ]
  })
}
```
 
### Ref 5 : Lambda + EventBridge
 
EventBridge déclenche la Lambda toutes les 5 minutes. La Lambda reçoit la liste des sites et le seuil de temps de réponse via ses variables d'environnement.
 
```hcl
resource "aws_cloudwatch_event_rule" "monitor" {
  name                = "${var.project_name}-trigger"
  schedule_expression = "rate(5 minutes)"
}
 
resource "aws_lambda_function" "monitor" {
  filename      = data.archive_file.lambda.output_path
  function_name = "${var.project_name}-checker"
  role          = aws_iam_role.lambda.arn
  handler       = "lambda_monitor.lambda_handler"
  runtime       = "python3.12"
  timeout       = 30
 
  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.uptime_results.name
      SNS_TOPIC_ARN  = aws_sns_topic.alerts.arn
      THRESHOLD_MS   = tostring(var.response_time_threshold_ms)
      WEBSITES       = jsonencode(var.websites_to_monitor)
    }
  }
}
```
 
## Déploiement
 
```bash
terraform init
terraform plan
terraform apply
```
 
> ⚠️ Confirme la souscription SNS en cliquant sur le lien reçu par email avant de recevoir les alertes.
 
## Tester manuellement
 
```bash
aws lambda invoke \
  --function-name uptime-monitor-checker \
  --payload '{}' \
  --cli-binary-format raw-in-base64-out \
  response.json
 
cat response.json
# {"statusCode": 200, "monitored": 3}
```
 
## Coût estimé
 
| Service | Utilisation | Coût mensuel |
|---|---|---|
| Lambda | ~8 640 exécutions/mois (toutes les 5 min) | ~$0.00 (Free Tier) |
| EventBridge | 1 règle | $0.00 (gratuit) |
| DynamoDB | PAY_PER_REQUEST · quelques KB/mois | ~$0.00 (Free Tier) |
| SNS | Quelques emails/mois | ~$0.00 (Free Tier) |
| CloudWatch Logs | Logs Lambda | ~$0.00 (Free Tier) |
| **Total** | | **~$0.00/mois** |
 
 
## Note
 
La vérification de contenu n'est pas implémentée dans cette version — la Lambda vérifie l'accessibilité, le code HTTP et le temps de réponse. Le projet est un exercice de monitoring serverless, non une solution de production (pas de retry logic, pas de multi-région).
 
[⬆️ Retour au menu](#aws-uptime-monitor)
 
---
 
## English
 
## Objective
 
This project deploys a fully serverless uptime monitoring system on AWS. A Lambda function triggers automatically every 5 minutes via EventBridge and checks each monitored site on three criteria: availability, response time and HTTP code. If anything fails, an email alert is sent immediately via SNS. Every result is stored in DynamoDB with a 30-day TTL.
 
## Problem Solved
 
A website going down costs customers, revenue and trust. Without automated monitoring, outages are often discovered by customers before the technical team. This project detects failures in under 5 minutes and alerts instantly.
 
## Skills Learned
 
- Serverless Lambda deployment with Terraform
- Scheduled task automation with EventBridge
- Time-series storage in DynamoDB with automatic TTL
- Real-time alert notifications via SNS
- Least-privilege principle applied to Lambda IAM roles
- CI/CD pipeline with GitHub Actions
## Tools Used
 
- Terraform (Infrastructure as Code)
- AWS: Lambda · DynamoDB · SNS · EventBridge · IAM · CloudWatch
- Python 3.12
## Architecture
 
```
EventBridge (rate: 5 minutes)
    → Lambda (lambda_monitor.py)
        → urllib: checks availability + response time + HTTP code
            → DynamoDB: stores each result (30-day TTL)
            → SNS → Email alert if status != OK
```
 
## What the Lambda checks
 
For each monitored site, three checks:
 
| Check | Alert condition | Status |
|---|---|---|
| Availability | urllib exception (timeout, DNS, connection) | `DOWN` |
| HTTP code | Code != 200 | `ERROR` |
| Response time | Exceeds defined threshold (default 3000ms) | `SLOW` |
 
## Steps
 
### Ref 1: Variables
 
```hcl
variable "websites_to_monitor" {
  type    = list(string)
  default = [
    "https://www.google.com",
    "https://github.com",
    "https://aws.amazon.com"
  ]
}
 
variable "response_time_threshold_ms" {
  type    = number
  default = 3000
}
```
 
### Ref 2: DynamoDB — result storage
 
The DynamoDB table uses `PAY_PER_REQUEST` — no capacity to provision. The composite key `website_url + timestamp` allows storing and querying history per site. TTL automatically deletes entries after 30 days.
 
```hcl
resource "aws_dynamodb_table" "uptime_results" {
  name         = "${var.project_name}-results"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "website_url"
  range_key    = "timestamp"
 
  attribute { name = "website_url" type = "S" }
  attribute { name = "timestamp"   type = "S" }
 
  ttl {
    attribute_name = "ttl"
    enabled        = true
  }
}
```
 
### Ref 3: SNS — email alerts
 
```hcl
resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"
}
 
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}
```
 
### Ref 4: IAM Role — least privilege
 
The Lambda only has the permissions it strictly needs: write to DynamoDB, publish to SNS, and write CloudWatch logs.
 
```hcl
resource "aws_iam_role_policy" "lambda" {
  role = aws_iam_role.lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow" Action = ["dynamodb:PutItem","dynamodb:GetItem"]
        Resource = [aws_dynamodb_table.uptime_results.arn] },
      { Effect = "Allow" Action = ["sns:Publish"]
        Resource = [aws_sns_topic.alerts.arn] },
      { Effect = "Allow" Action = ["logs:*"] Resource = ["*"] }
    ]
  })
}
```
 
### Ref 5: Lambda + EventBridge
 
EventBridge triggers the Lambda every 5 minutes. The Lambda receives the list of sites and the response time threshold via environment variables.
 
```hcl
resource "aws_cloudwatch_event_rule" "monitor" {
  name                = "${var.project_name}-trigger"
  schedule_expression = "rate(5 minutes)"
}
 
resource "aws_lambda_function" "monitor" {
  filename      = data.archive_file.lambda.output_path
  function_name = "${var.project_name}-checker"
  role          = aws_iam_role.lambda.arn
  handler       = "lambda_monitor.lambda_handler"
  runtime       = "python3.12"
  timeout       = 30
 
  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.uptime_results.name
      SNS_TOPIC_ARN  = aws_sns_topic.alerts.arn
      THRESHOLD_MS   = tostring(var.response_time_threshold_ms)
      WEBSITES       = jsonencode(var.websites_to_monitor)
    }
  }
}
```
 
## Deployment
 
```bash
terraform init
terraform plan
terraform apply
```
 
> ⚠️ Confirm the SNS subscription by clicking the link received by email before alerts can be delivered.
 
## Manual test
 
```bash
aws lambda invoke \
  --function-name uptime-monitor-checker \
  --payload '{}' \
  --cli-binary-format raw-in-base64-out \
  response.json
 
cat response.json
# {"statusCode": 200, "monitored": 3}
```
 
## Estimated Cost
 
| Service | Usage | Monthly cost |
|---|---|---|
| Lambda | ~8,640 executions/month (every 5 min) | ~$0.00 (Free Tier) |
| EventBridge | 1 rule | $0.00 (free) |
| DynamoDB | PAY_PER_REQUEST · a few KB/month | ~$0.00 (Free Tier) |
| SNS | A few emails/month | ~$0.00 (Free Tier) |
| CloudWatch Logs | Lambda logs | ~$0.00 (Free Tier) |
| **Total** | | **~$0.00/month** |
 
 
## Note
 
Content verification is not implemented in this version — the Lambda checks availability, HTTP code and response time. This project is a serverless monitoring exercise, not a production solution (no retry logic, no multi-region).
 
[⬆️ Back to menu](#aws-uptime-monitor)
 
---
 
## Deutsch
 
## Ziel
 
Dieses Projekt stellt ein vollständig serverloses Uptime-Monitoring-System auf AWS bereit. Eine Lambda-Funktion wird automatisch alle 5 Minuten über EventBridge ausgelöst und prüft jede überwachte Website anhand von drei Kriterien: Verfügbarkeit, Antwortzeit und HTTP-Code. Bei einer Anomalie wird sofort eine E-Mail-Benachrichtigung über SNS gesendet. Jedes Ergebnis wird mit einem TTL von 30 Tagen in DynamoDB gespeichert.
 
## Gelöstes Problem
 
Ein ausgefallenes Website kostet Kunden, Umsatz und Vertrauen. Ohne automatisches Monitoring werden Ausfälle oft von Kunden vor dem technischen Team entdeckt. Dieses Projekt erkennt Ausfälle in weniger als 5 Minuten und benachrichtigt sofort.
 
## Erworbene Kompetenzen
 
- Serverlose Lambda-Bereitstellung mit Terraform
- Automatisierung geplanter Aufgaben mit EventBridge
- Zeitreihenspeicherung in DynamoDB mit automatischem TTL
- Echtzeit-Benachrichtigungen über SNS
- Least-Privilege-Prinzip für Lambda-IAM-Rollen
- CI/CD-Pipeline mit GitHub Actions
## Verwendete Werkzeuge
 
- Terraform (Infrastructure as Code)
- AWS: Lambda · DynamoDB · SNS · EventBridge · IAM · CloudWatch
- Python 3.12
## Architektur
 
```
EventBridge (rate: 5 Minuten)
    → Lambda (lambda_monitor.py)
        → urllib: prüft Verfügbarkeit + Antwortzeit + HTTP-Code
            → DynamoDB: speichert jedes Ergebnis (30-Tage-TTL)
            → SNS → E-Mail-Alarm wenn Status != OK
```
 
## Was die Lambda prüft
 
Für jede überwachte Website drei Prüfungen:
 
| Prüfung | Alarmbedingung | Status |
|---|---|---|
| Verfügbarkeit | urllib-Ausnahme (Timeout, DNS, Verbindung) | `DOWN` |
| HTTP-Code | Code != 200 | `ERROR` |
| Antwortzeit | Überschreitet definierten Schwellenwert (Standard 3000ms) | `SLOW` |
 
## Schritte
 
### Ref 1: Variablen
 
```hcl
variable "websites_to_monitor" {
  type    = list(string)
  default = [
    "https://www.google.com",
    "https://github.com",
    "https://aws.amazon.com"
  ]
}
 
variable "response_time_threshold_ms" {
  type    = number
  default = 3000
}
```
 
### Ref 2: DynamoDB — Ergebnisspeicherung
 
Die DynamoDB-Tabelle verwendet `PAY_PER_REQUEST` — keine Kapazität zu provisionieren. Der zusammengesetzte Schlüssel `website_url + timestamp` ermöglicht das Speichern und Abfragen des Verlaufs pro Website. TTL löscht Einträge automatisch nach 30 Tagen.
 
```hcl
resource "aws_dynamodb_table" "uptime_results" {
  name         = "${var.project_name}-results"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "website_url"
  range_key    = "timestamp"
 
  ttl {
    attribute_name = "ttl"
    enabled        = true
  }
}
```
 
### Ref 3: SNS — E-Mail-Benachrichtigungen
 
```hcl
resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"
}
 
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}
```
 
### Ref 4: IAM Role — Least Privilege
 
Die Lambda hat nur die unbedingt erforderlichen Berechtigungen: Schreiben in DynamoDB, Veröffentlichen in SNS und Schreiben von CloudWatch-Logs.
 
### Ref 5: Lambda + EventBridge
 
EventBridge löst die Lambda alle 5 Minuten aus. Die Lambda empfängt die Liste der Websites und den Antwortzeitgrenzwert über Umgebungsvariablen.
 
```hcl
resource "aws_cloudwatch_event_rule" "monitor" {
  name                = "${var.project_name}-trigger"
  schedule_expression = "rate(5 minutes)"
}
```
 
## Bereitstellung
 
```bash
terraform init
terraform plan
terraform apply
```
 
## Geschätzte Kosten
 
| Service | Nutzung | Monatliche Kosten |
|---|---|---|
| Lambda | ~8.640 Ausführungen/Monat | ~$0.00 (Free Tier) |
| EventBridge | 1 Regel | $0.00 (kostenlos) |
| DynamoDB | PAY_PER_REQUEST · wenige KB/Monat | ~$0.00 (Free Tier) |
| SNS | Wenige E-Mails/Monat | ~$0.00 (Free Tier) |
| CloudWatch Logs | Lambda-Logs | ~$0.00 (Free Tier) |
| **Gesamt** | | **~$0.00/Monat** |
 
## Hinweis
 
Die Inhaltsverifizierung ist in dieser Version nicht implementiert — die Lambda prüft Verfügbarkeit, HTTP-Code und Antwortzeit. Dieses Projekt ist eine serverlose Monitoring-Übung, keine Produktionslösung.
 
[⬆️ Zurück zum Menü](#aws-uptime-monitor)
