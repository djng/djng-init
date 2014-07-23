#!/usr/bin/env bash
#       __  _
#  ____/ / (_)___  ____ _
# / __  / / / __ \/ __ `/
#/ /_/ / / / / / / /_/ /
#\__,_/_/ /_/ /_/\__, /
#    /___/      /____/
{
	# Fail fast
	set -e

	# Test if given command exists
	checkcmd () {
		if hash $1 2>/dev/null; then
			printf "%-10s \xE2\x9C\x94\n" $1
		else
			printf "%-10s \xE2\x9D\x8C\n" $1
			printf "I require $1 but it's not installed. Aborting.\n";
			exit 1;
		fi
	}

	# Prefix ouptut with a star
	estar () {
		printf "\xE2\x98\x85 ${1}\n"
	}

	# Prefix ouptut with a newline and a star
	estarn () {
		printf "\n\xE2\x98\x85 ${1}\n"
	}

	# Greet
	estar "Hello ${USER}"
	estar "I guide you trough the setup process"

	# Download base project
	estarn "Downloading project"
	curl --progress-bar -0 https://github.com/djng/djng/archive/master.tar.gz | tar -zx

	# Check prerequsites
	estarn "Checking prerequisites"
	for i in bower git grunt heroku node npm pip virtualenv
	do
	   checkcmd "$i"
	done

	if [ ! -f server/.env ]; then
		# Read user information
		estarn "I need some basic information"
		read -e -p "Your name: " USER_NAME </dev/tty
		read -e -p "Your email: " USER_EMAIL </dev/tty
		read -e -p "Database user: " DB_USER </dev/tty
		read -e -s -p "Database password (typing will be hidden): " DB_PASSWORD </dev/tty
		printf "\n"
		read -e -p "Database name: " DB_NAME </dev/tty
		read -e -p "Database host: " -i "localhost" DB_HOST </dev/tty

		# Create .env file
		cat <<- EOF > server/.env
		DJANGO_DEBUG=True
		DJANGO_SECRET=`openssl rand -base64 32`
		DATABASE_URL=postgres://${DB_USER}:${DB_PASSWORD}@${DB_HOST}/${DB_NAME}
		DJANGO_FROM_MAIL=${USER_EMAIL}
		DJANGO_ADMINS=<${USER_NAME}> ${USER_EMAIL}
		DJANGO_MANAGERS=<${USER_NAME}> ${USER_EMAIL}
		EOF
	fi

	# Create virtual env and install requirements
	if [ ! -f venv/bin/activate ]; then
		estarn "Creating virtualenv and install requirements"
		virtualenv venv --no-site-packages
	else
		estarn "Installing requirements"
	fi

	source venv/bin/activate
	#pip install -r requirements.txt

	# Init db
	estarn "Initializing database"
	pushd server > /dev/null
	python manage.py migrate
	estarn "Creating Django admin user"
	python manage.py createsuperuser </dev/tty
	popd > /dev/null

	estarn "Installing client dependencies"
	pushd client > /dev/null
	npm install
	bower install
	popd > /dev/null

	estarn "Creating git repo"
	git init
	git add .
	git commit -m "inital release"

	estarn "Login to heroku and create app"
	heroku login </dev/tty
	URL=$(heroku create | egrep -o 'https?://[^ ]+')

	# Add heroku addons
	estarn "Adding heroku addons"
	heroku addons:add heroku-postgresql
	heroku addons:add pgbackups:auto-week
	heroku addons:add sendgrid
	heroku addons:add papertrail
	heroku addons:add newrelic:stark
	heroku plugins:install git://github.com/ddollar/heroku-config.git

	# Setup heroku server env
	estarn "Configuring heroku environment"
	heroku config:set DJANGO_SECRET=`openssl rand -base64 32`
	heroku config:set DJANGO_DEBUG=False
	heroku config:push --env=server/.env

	# Deploy
	estarn "Deploying"
	git push heroku master

	# Initalize heroku database
	estarn "Initializing heroku database"
	heroku run python server/manage.py migrate
	estarn "Creating Django admin user on heroku"
	heroku run python server/manage.py createsuperuser </dev/tty

	printf "\n\xE2\x98\x85 Done!\nVisit your app at %s\n" ${URL}
}