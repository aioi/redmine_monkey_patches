redmine_monkey_patches
======================

Patches applied to our redmine installation

* monkey_patches.rb
	* patch the git adapter to only process "master" and "development" branches
	* patch the mailer to return all issues if no days limit is is speficied rather than defaulting to issues due in the next 7 days.
* patch_parent_task_date_handling.diff
	* sub-tasks' start and end dates no longer update parent task dates
	* parent task start and end date fields are now editable on issue screen

Installation
------------

* Copy `monkey_patches.rb` to redmine's `config/initializers/` directory
* Run `git apply patch_parent_task_date_handling.diff` from redmine root