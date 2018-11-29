TEST_COMMAND = ENV["BUMMR_TEST"] || "bundle exec rake"
BASE_BRANCH = ENV["BASE_BRANCH"] || "master"

module Bummr
  class CLI < Thor
    include Bummr::Log
    include Bummr::Scm

    desc "check", "Run automated checks to see if bummr can be run"
    def check(fullcheck=true)
      Bummr::Check.instance.check(fullcheck)
    end

    desc "update", "Update outdated gems, run tests, bisect if tests fail"
    method_option :all, type: :boolean, default: false
    method_option :group, type: :string
    def update
      system("bundle install")
      ask_questions

      if yes? "Are you ready to use Bummr? (y/n)"
        check
        log("Bummr update initiated #{Time.now}")

        outdated_gems = Bummr::Outdated.instance.outdated_gems(
          all_gems: options[:all], group: options[:group]
        )

        if outdated_gems.empty?
          puts "No outdated gems to update".color(:green)
        else
          Bummr::Updater.new(outdated_gems).update_gems

          git.rebase_interactive(BASE_BRANCH)
          test
        end
      else
        puts "Thank you!".color(:green)
      end
    end

    desc "test", "Test for a successful build and bisect if necesssary"
    def test
      check(false)

      if yes? "Do you want to test the build now?"
        system "bundle install"
        puts "Testing the build!".color(:green)

        if system(TEST_COMMAND) == false
          bisect
        else
          puts "Passed the build!".color(:green)
          puts "See log/bummr.log for details".color(:yellow)
        end
      end
    end

    desc "bisect", "Find the bad commit, remove it, test again"
    def bisect
      check(false)

      if yes? "Would you like to bisect in order to find which gem is causing " +
              "your build to break? (y/n)"
        Bummr::Bisecter.instance.bisect
      end
    end

    desc "remove_commit", "Remove a commit from the history"
    def remove_commit(sha)
      Bummr::Remover.instance.remove_commit(sha)
    end

    private

    def ask_questions
      puts "Bummr #{VERSION}"
      puts "To run Bummr, you must:"
      puts "- Be in the root path of a clean git branch off of " + "#{BASE_BRANCH}".color(:yellow)
      puts "- Have no commits or local changes"
      puts "- Have a 'log' directory, where we can place logs"
      puts "- Have your build configured to fail fast (recommended)"
      puts "- Have locked any Gem version that you don't wish to update in your Gemfile"
      puts "- It is recommended that you lock your versions of `ruby` and `rails` in your `Gemfile`"
      puts "\n"
      puts "Your test command is: " + "'#{TEST_COMMAND}'".color(:yellow)
      puts "\n"
      print_received_options
    end

    def print_received_options
      unless options.empty?
        puts "Bummr will run with the following options:"

        if !options[:all].nil?
          puts "--all: ".color(:yellow) +
            "Bummr will also include indirect dependencies (the default is direct dependencies only)"
        end

        if !options[:group].nil?
          puts "--group #{options[:group]}: ".color(:yellow) +
            "Only gems belonging to the #{options[:group].color(:yellow)} group will be updated"
        end
      end
    end
  end
end
