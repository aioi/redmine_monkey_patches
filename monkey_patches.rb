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

