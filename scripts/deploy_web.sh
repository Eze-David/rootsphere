#!/bin/bash
set -e

# Google Maps key for the website lives in .env (not committed).
MAPS_WEB_API_KEY=$(grep -E '^MAPS_WEB_API_KEY=' .env | cut -d= -f2-)
if [ -z "$MAPS_WEB_API_KEY" ]; then
  echo "MAPS_WEB_API_KEY is missing from .env" >&2
  exit 1
fi

echo "Building Rootsphere for web..."
flutter build web --release

echo "Adding the Maps API key..."
sed -i.bak "s/MAPS_WEB_API_KEY/$MAPS_WEB_API_KEY/" build/web/index.html
rm build/web/index.html.bak

echo "Copying Vercel config..."
cp vercel.json build/web/

echo "Deploying to Vercel..."
vercel --prod --yes build/web

echo "Done!"
