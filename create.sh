#!/bin/bash

RUBY_VERSION="1.9.3"
RAILS_VERSION="3.2.13"
APP_NAME="DemoApp2"

cd $(dirname $0)

# We want to use rvm to manage our Ruby versions and gems
rvm -v >/dev/null 2>&1
if [ "$?" != "0" ] ; then
	# This command should install Ruby, Rails, and RVM if they do not exist.
	curl -L https://get.rvm.io | bash -s stable --rails --autolibs=enable
fi
rvm use ${RUBY_VERSION}
if [ "$?" != "0" ] ; then
	rvm install ${RUBY_VERSION}
	rvm use ${RUBY_VERSION}
fi
# We want to use the rails-api gem to generate our API base structure.
rails-api --version >/dev/null 2>&1
if [ "$?" != "0" ] ; then
	gem install rails-api
fi

# Rails-API has handy templates that make lots of the boilerplate structure for you.
rails-api new ${APP_NAME}

cd ${APP_NAME}

# The generated app has a Gemfile but we have some specific requirements:
#  - Let's encode our Ruby version and gemset in this app's Gemfile.
#    RVM and Heroku can both extract from the Gemfile.
#  - We need to include the framework gems, starting with rails but also rails-api.
#  - We'll encode our type data in our model using HoboFields
#  - We'll be running locally and on Heroku; Heroku provides a postgresql database, while locally we'll use sqlite.
#  - Heroku recommends using thin as production web server.
cat >Gemfile <<EOF
source 'https://rubygems.org'
#ruby${RUBY_VERSION}@${APP_NAME}

gem 'rails', '${RAILS_VERSION}'
gem 'rails-api'
gem 'hobo_fields'
gem 'pg'
gem 'sqlite3'
gem 'thin'
EOF

# bundle is the tool which will install all of our gems as specified by our Gemfile.
# additionally, it will figure out if they have dependencies, and install those too.
bundle install

# First, I want a model of a mobile device.  A mobile device can send us a push token.
cat >app/models/mobile_device.rb <<EOF
class MobileDevice < ActiveRecord::Base
  fields do
  	platform :string
    push_token :string
  	timestamps
  end

  attr_accessible :platform

  belongs_to :User
  has_many :PushTokens
end
EOF
# A user can have many mobile devices
# We define an anonymous user as well.
cat >app/models/user.rb <<EOF
class User < ActiveRecord::Base
  fields do
  	name :string
  	timestamps
  end

  attr_accessible :name

  has_many :PushTokens, :through => :MobileDevices

  def self.anonymous
		User.find_or_create_by_name('anonymous')
	end
end
EOF

# I'm going to use a tool called HoboFields to automatically create the database schema from the models.
# You might have noticed the "fields do" section above in each model.
# HoboFields will now generate our database schema, expressed as a series of migrations.
rails generate hobo:migration -g -n

# rake is a tool for performing maintenance tasks on a Rails app, such as applying DB migrations.
# bundle is the tool which we used to install all our gems, and conveniently knows where they all are
# in general it's not a bad idea to wrap your commands which have to operate in your project environment with "bundle exec"
# Note that since we're using sqlite3 for development (and this is a rails expected default) the rails api generator
# has created a db/development.sqlite3 database for us.  Otherwise we could invoke "bundle exec rake db:create"
bundle exec rake db:migrate

# We've got models and we've got a database but we have no controllers!  Quick, add some endpoints.
cat >app/controllers/mobile_devices_controller.rb <<EOF
class MobileDevicesController < ApplicationController
  # GET /mobiledevices
  # GET /mobiledevices.json
  def index
    @mobile_devices = MobileDevice.all

    render json: @mobile_devices
  end

  # GET /mobiledevices/1
  # GET /mobiledevices/1.json
  def show
    @mobile_device = MobileDevice.find(params[:id])

    render json: @mobile_device
  end
end
EOF

# And we need a route for this
cat >config/routes.rb <<EOF
${APP_NAME}::Application.routes.draw do
  resources :mobiledevices, :controller => "MobileDevices" do
    collection do
      get 'index'
    end
    member do
      get 'show'
    end
  end
EOF

# We're all done adding routes
cat >>config/routes.rb <<EOF
end
EOF

# We can confirm that we've hooked up our controllers and routed to them as follows:
bundle exec rake routes

# Now let's run this thing.
rails server
