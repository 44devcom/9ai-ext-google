#! /bin/bash

docker compose run --rm gcp gcloud compute instances create free-e2-micro \
  --zone=us-west1-b \
  --machine-type=e2-micro \
  --image-family=debian-13 \
  --image-project=debian-cloud \
  --boot-disk-size=30GB \
  --boot-disk-type=pd-standard \
  --network-tier=STANDARD
