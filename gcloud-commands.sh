#!/usr/bin/env bash
# =============================================================================
#  GCP Demo App — Full gcloud CLI Playbook
#  Covers Q1 (Flex + NEG + LB), Q1-Standard (VPC NAT), Q2 (manual scaling +
#  traffic split), Q3 (Cloud Run deploy), Q4 (revision split), Q5 (internal)
# =============================================================================

set -euo pipefail

# ── EDIT THESE ───────────────────────────────────────────────
PROJECT_ID="your-project-id"
REGION="us-central1"
ZONE="us-central1-a"
IMAGE="gcr.io/${PROJECT_ID}/gcp-demo-app"
CONNECTOR_NAME="demo-vpc-connector"
VPC_NETWORK="default"
CR_SERVICE="gcp-demo-app"
# ─────────────────────────────────────────────────────────────

gcloud config set project "$PROJECT_ID"


# ╔══════════════════════════════════════════════════════════════╗
# ║  Q1-A: App Engine FLEX + NEG + HTTP(S) Load Balancer        ║
# ╚══════════════════════════════════════════════════════════════╝

## 1. Build & push Docker image
gcloud builds submit --tag "$IMAGE" .

## 2. Deploy to App Engine Flexible
gcloud app deploy app-flex.yaml --quiet

## 3. Reserve a global static IP
gcloud compute addresses create demo-static-ip \
  --global \
  --ip-version=IPV4

STATIC_IP=$(gcloud compute addresses describe demo-static-ip \
  --global --format="get(address)")
echo "Static IP: $STATIC_IP"

## 4. Create a Serverless NEG pointing at App Engine
gcloud compute network-endpoint-groups create demo-appengine-neg \
  --region="$REGION" \
  --network-endpoint-type=serverless \
  --app-engine-app

## 5. Create backend service + attach NEG
gcloud compute backend-services create demo-backend \
  --load-balancing-scheme=EXTERNAL \
  --global

gcloud compute backend-services add-backend demo-backend \
  --global \
  --network-endpoint-group=demo-appengine-neg \
  --network-endpoint-group-region="$REGION"

## 6. URL map → target HTTP proxy → forwarding rule
gcloud compute url-maps create demo-url-map \
  --default-service=demo-backend

gcloud compute target-http-proxies create demo-http-proxy \
  --url-map=demo-url-map

gcloud compute forwarding-rules create demo-forwarding-rule \
  --address=demo-static-ip \
  --global \
  --target-http-proxy=demo-http-proxy \
  --ports=80

## 7. Verify
echo "▶ Verify (allow 2-5 min for LB to propagate):"
echo "  curl http://$STATIC_IP/health"
curl -s --retry 10 --retry-delay 15 "http://$STATIC_IP/health" || true


# ╔══════════════════════════════════════════════════════════════╗
# ║  Q1-B: App Engine STANDARD + VPC Connector + Cloud NAT      ║
# ╚══════════════════════════════════════════════════════════════╝

## 1. Create Serverless VPC Access connector
gcloud compute networks vpc-access connectors create "$CONNECTOR_NAME" \
  --region="$REGION" \
  --network="$VPC_NETWORK" \
  --range="10.8.0.0/28"

## 2. Reserve a regional static IP for Cloud NAT
gcloud compute addresses create demo-nat-ip \
  --region="$REGION"

NAT_IP=$(gcloud compute addresses describe demo-nat-ip \
  --region="$REGION" --format="get(address)")
echo "NAT Static IP: $NAT_IP"

## 3. Create Cloud Router + Cloud NAT using that IP
gcloud compute routers create demo-router \
  --region="$REGION" \
  --network="$VPC_NETWORK"

gcloud compute routers nats create demo-nat \
  --router=demo-router \
  --region="$REGION" \
  --nat-external-ip-pool=demo-nat-ip \
  --nat-custom-subnet-ip-ranges="$VPC_NETWORK"

## 4. Deploy Standard app (connector name set in app-standard.yaml)
#    Edit app-standard.yaml → vpc_access_connector.name first!
gcloud app deploy app-standard.yaml --quiet

## 5. Verify: call an IP-echo service from the app
echo "▶ App should call an external IP-echo:"
APP_URL=$(gcloud app browse --no-launch-browser 2>&1 | tail -1)
curl -s "$APP_URL/api/info"
echo ""
echo "  External requests should originate from: $NAT_IP"
echo "  Confirm at: https://api.ipify.org (call from inside the app)"


# ╔══════════════════════════════════════════════════════════════╗
# ║  Q2: Manual Scaling + Traffic Splitting (gcloud CLI only)   ║
# ╚══════════════════════════════════════════════════════════════╝

## 1. Deploy v1 (promote as default)
gcloud app deploy app-standard.yaml \
  --version=v1 \
  --promote \
  --quiet

## 2. Deploy v2 WITHOUT promoting it
gcloud app deploy app-v2.yaml \
  --version=v2 \
  --no-promote \
  --quiet

## 3. List versions
gcloud app versions list --service=default

## 4. Split traffic: 80% → v1, 20% → v2
gcloud app services set-traffic default \
  --splits=v1=0.8,v2=0.2 \
  --split-by=random

## 5. Verify split
gcloud app services describe default
echo "▶ Traffic split verification (run multiple times):"
for i in {1..10}; do
  curl -s "$(gcloud app browse --no-launch-browser 2>&1 | tail -1)/api/info" \
    | grep '"version"'
done


# ╔══════════════════════════════════════════════════════════════╗
# ║  Q3: Cloud Run — Containerize & Deploy                      ║
# ╚══════════════════════════════════════════════════════════════╝

## 1. Build & push image (reuse from Q1 or rebuild)
gcloud builds submit --tag "$IMAGE" .

## 2. Deploy to Cloud Run (publicly accessible)
gcloud run deploy "$CR_SERVICE" \
  --image="$IMAGE" \
  --region="$REGION" \
  --platform=managed \
  --allow-unauthenticated \
  --port=8080 \
  --set-env-vars="APP_VERSION=v1,APP_COLOR=#6366f1" \
  --revision-suffix=v1

## 3. Get the service URL
CR_URL=$(gcloud run services describe "$CR_SERVICE" \
  --region="$REGION" \
  --format="get(status.url)")
echo "Cloud Run URL: $CR_URL"

## 4. Verify
curl -s "$CR_URL/health"


# ╔══════════════════════════════════════════════════════════════╗
# ║  Q4: Cloud Run — Deploy v2 Revision + Traffic Split 30/70   ║
# ╚══════════════════════════════════════════════════════════════╝

## 1. Deploy new revision (v2, no traffic yet)
gcloud run deploy "$CR_SERVICE" \
  --image="$IMAGE" \
  --region="$REGION" \
  --platform=managed \
  --allow-unauthenticated \
  --port=8080 \
  --set-env-vars="APP_VERSION=v2,APP_COLOR=#ec4899" \
  --revision-suffix=v2 \
  --no-traffic

## 2. Split traffic: 70% → v1, 30% → v2
gcloud run services update-traffic "$CR_SERVICE" \
  --region="$REGION" \
  --to-revisions="${CR_SERVICE}-v1=70,${CR_SERVICE}-v2=30"

## 3. Verify allocation
gcloud run services describe "$CR_SERVICE" \
  --region="$REGION" \
  --format="yaml(spec.traffic)"

## 4. Live verification (check 'version' field across responses)
echo "▶ Sampling 10 requests — expect ~70% v1, ~30% v2:"
for i in {1..10}; do
  curl -s "$CR_URL/api/info" | grep '"version"'
done


# ╔══════════════════════════════════════════════════════════════╗
# ║  Q5: Cloud Run — Internal-only (VPC/internal clients only)  ║
# ╚══════════════════════════════════════════════════════════════╝

## 1. Update service ingress to internal only
gcloud run services update "$CR_SERVICE" \
  --region="$REGION" \
  --ingress=internal

## 2. Verify public access is BLOCKED
echo "▶ Public access should return 403:"
curl -v "$CR_URL/health" 2>&1 | grep -E "403|Forbidden|< HTTP"

## 3. Verify internal access works (run from a VM inside the VPC)
#    SSH into a GCE VM in the same VPC, then:
echo "▶ From inside VPC:"
echo "  gcloud compute ssh my-internal-vm --zone=$ZONE --command=\""
echo "    curl -s $CR_URL/health\""
echo "  \""

## 4. (Optional) Restore public access after testing
# gcloud run services update "$CR_SERVICE" \
#   --region="$REGION" \
#   --ingress=all

echo ""
echo "✅ All steps complete."
