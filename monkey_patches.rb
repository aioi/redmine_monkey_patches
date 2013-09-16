# Monkey patch Better Gantt Chart plugin to not update sub-tasks, which 
# crashes with out patch to parent task date handling.
module RedmineBetterGanttChart
  module IssueDependencyPatch
    module InstanceMethods
      def process_child_issues(issue)
        # noop
      end
    end
  end
end

# Monkey patch the git adapter, to only return "master" or "development"
# branches. Publishing feature and staging branches was having unintended
# side-effects of updating issue references and statuses in Redmine.

require 'redmine/scm/adapters/git_adapter.rb'

module Redmine
  module Scm
    module Adapters
      class GitAdapter

        alias_method :branches_original, :branches

        def branches(*args)
          all_branches = branches_original(*args)
          all_branches.find_all { |b| ["development", "master"].include?(b) }
        end
      end
    end
  end
end


# Monkey patch the mailer, to return all issues if no days limit is speficied rather
# than defaulting to issues due in the next 7 days.
require 'mailer'
class Mailer
  def self.reminders(options={})
    days = options[:days]
    project = options[:project] ? Project.find(options[:project]) : nil
    tracker = options[:tracker] ? Tracker.find(options[:tracker]) : nil
    user_ids = options[:users]

    scope = Issue.open.where("#{Issue.table_name}.assigned_to_id IS NOT NULL" +
      " AND #{Project.table_name}.status = #{Project::STATUS_ACTIVE}"
    )
    scope = scope.where("#{Issue.table_name}.due_date <= ?", days.day.from_now.to_date) if days.present?
    scope = scope.where(:assigned_to_id => user_ids) if user_ids.present?
    scope = scope.where(:project_id => project.id) if project
    scope = scope.where(:tracker_id => tracker.id) if tracker

    issues_by_assignee = scope.includes(:status, :assigned_to, :project, :tracker).all.group_by(&:assigned_to)
    issues_by_assignee.keys.each do |assignee|
      if assignee.is_a?(Group)
        assignee.users.each do |user|
          issues_by_assignee[user] ||= []
          issues_by_assignee[user] += issues_by_assignee[assignee]
        end
      end
    end

    issues_by_assignee.each do |assignee, issues|
      reminder(assignee, issues, days).deliver if assignee.is_a?(User) && assignee.active?
    end
  end
end
