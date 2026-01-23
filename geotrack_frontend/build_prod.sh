#!/bin/bash
TIMESTAMP=$(date +%m%d%H%M)
VERSION="1.0.5"

echo " Build de la version $VERSION (Code: $TIMESTAMP)"

flutter build apk --release --build-name="$VERSION" --build-number="$TIMESTAMP"