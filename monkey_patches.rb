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

# Monkey patch Issue model to prevent update of parent tasks' start and end
# dates when sub-tasks are updated.
class Issue
  def recalculate_attributes_for(issue_id)
    if issue_id && p = Issue.find_by_id(issue_id)
      priority = highest priority of children
      if priority_position = p.children.maximum("#{IssuePriority.table_name}.position", :joins => :priority)
        p.priority = IssuePriority.find_by_position(priority_position)
      end

      # start/due dates = lowest/highest dates of children
      # p.start_date = p.children.minimum(:start_date)
      # p.due_date = p.children.maximum(:due_date)
      # if p.start_date && p.due_date && p.due_date < p.start_date
      #   p.start_date, p.due_date = p.due_date, p.start_date
      # end

      # done ratio = weighted average ratio of leaves
      unless Issue.use_status_for_done_ratio? && p.status && p.status.default_done_ratio
        leaves_count = p.leaves.count
        if leaves_count > 0
          average = p.leaves.average(:estimated_hours).to_f
          if average == 0
            average = 1
          end
          done = p.leaves.sum("COALESCE(estimated_hours, #{average}) * (CASE WHEN is_closed = #{connection.quoted_true} THEN 100 ELSE COALESCE(done_ratio, 0) END)", :joins => :status).to_f
          progress = done / (average * leaves_count)
          p.done_ratio = progress.round
        end
      end

      # estimate = sum of leaves estimates
      p.estimated_hours = p.leaves.sum(:estimated_hours).to_f
      p.estimated_hours = nil if p.estimated_hours == 0.0

      # ancestors will be recursively updated
      p.save(:validate => false)
    end
  end  
end