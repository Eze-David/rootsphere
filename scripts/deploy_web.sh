#!/bin/bash
set -e

echo "Building Rootsphere for web..."
flutter build web --release

echo "Copying Vercel config..."
cp vercel.json build/web/

echo "Deploying to Vercel..."
vercel --prod --yes build/web

echo "Done!"
