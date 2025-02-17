#!/usr/bin/env sh

# This file is for debugging this add-on by directly doing what it does but
# without installing it. That way any issues with the add-on itself might be
# be identified.
#
# First, install XQuartz (and ONLY XQuartz) according to the instructions at
# https://github.com/TravisCarden/ddev-drupal-xb-dev#prerequisites-xquartz
# (Stop after configuring XQuartz--do not continue with the steps in the README.
#
# Then run the following commands on your host machine to clone the
# repository fresh and run the script:
#
#   cd ~/Projects/temp # This can be anywhere you want.
#   git clone git@github.com:TravisCarden/ddev-drupal-xb-dev.git
#   cd ddev-drupal-xb-dev
#   ./tests/debug.sh

cd "$(dirname "$0")/../var" && clear || exit 1
clear; set -ev

PROJECT_DIR="debug"
PROJECT_NAME=drupal-xb-dev-debug
MODULE_PATH=web/modules/contrib/experience_builder

# Clean up from previous runs.
PROJECT_EXISTS=$(ddev list | grep -q $PROJECT_NAME) || true
if [ -d $PROJECT_DIR ] || [ -n "$PROJECT_EXISTS" ]; then
  yes | ddev clean $PROJECT_NAME || true
  ddev remove --unlist $PROJECT_NAME || true
  rm -rf $PROJECT_DIR || true
fi

mkdir $PROJECT_DIR || true
cd $PROJECT_DIR || exit 1

# Create a new project.
ddev config \
  --project-name=$PROJECT_NAME \
  --project-type=drupal \
  --php-version=8.3 \
  --docroot=web
ddev composer create drupal/recommended-project:^11.x-dev --no-install

ddev get ddev/ddev-selenium-standalone-chrome

# Require Drush, but don't install yet for performance reasons.
ddev composer \
  require \
  --no-install \
  drush/drush

# Place the Experience Builder module via Git for development. Require
# it with Composer to test its composer.json and place dependencies.
git clone \
git@git.drupal.org:project/experience_builder.git \
  $MODULE_PATH
ddev composer config \
  repositories.xb \
  path \
  $MODULE_PATH
ddev composer require drupal/experience_builder

# Install Drupal and the Experience Builder module.
ddev drush site:install -y \
  --account-name=admin \
  --account-pass=admin \
  --site-name="XB Local Dev"
ddev drush en -y experience_builder

# Create a symlink to the module at a more convenient
# location for editing, at the project root.
ln -s $MODULE_PATH experience_builder

# Set environment variables for testing.
cat > "$MODULE_PATH/ui/.env" << EOF
BASE_URL='http://web'
DRUPAL_TEST_DB_URL=sqlite://web/sites/default/files/db.sqlite
DB_URL=sqlite://web/sites/default/files/db.sqlite
VITE_SERVER_ORIGIN='http://localhost:5173'
EOF

# shellcheck disable=SC2016
echo '$settings["extension_discovery_scan_tests"] = TRUE;' >> web/sites/default/settings.ddev.php

# Configure container.
cp ../../config.drupal-xb-dev.yaml \
  .ddev/config.drupal-xb-dev.yaml

# Initialize the environment.
ddev start

# Build npm assets.
ddev exec \
  --dir "/var/www/html/$MODULE_PATH/ui" \
  "npm ci"

# Add the host IP to the allowed X11 hosts and run XQuartz.
xhost +

# xhost should open XQuartz automatically, but just to be sure...
open -a XQuartz

# Run Cypress.
ddev exec \
  --dir "/var/www/html/$MODULE_PATH/ui" \
  "node_modules/.bin/cypress open --browser electron --project ."
