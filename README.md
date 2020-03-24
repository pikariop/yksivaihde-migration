# yvnet-migration

Migrating legacy bbpress to Discourse

## Usage

- Install local mysql server and set up a user, import bbpress dump
- Install development environment https://meta.discourse.org/t/beginners-guide-to-install-discourse-on-ubuntu-for-development/14727
- Copy `bbpress.rb` to `discourse/script/import_scripts/`
- Copy `base.rb` to `discourse/script/import_scripts/`
- Ensure `rbenv` is installed and correct Ruby version is selected
- Install `default-libmysqlclient-dev`
- https://meta.discourse.org/t/migrating-from-bbpress-wordpress-plugin-to-discourse/48876
- import settings from beta before migrating to local to avoid bumping into username length restrictions etc

## Import speeds 
- users 200...250 items/min
- posts 100ish hours
- permalinks 2h45min
