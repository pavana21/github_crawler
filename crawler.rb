#!/usr/bin/env ruby
# frozen_string_literal: true

#---------------------------Problem Statement-----------------------------------
# We believe that commits in a proper pull request stand on their own. There should be no “editing
# history”, meaning that each changed row in each file should only be affected by a single commit
# only.
#
# Provide a github link of your solution for the following:
#     Crawl the "rails/rails" github repo and list all the pull requests where there are rows in files
# affected by multiple commits. Please provide links to the specific rows as well.
#-------------------------------------------------------------------------------

require 'rubygems'
require 'octokit'
require 'pry'

# GITHUB_PAT = ENV['GITHUN_PERSONAL_TOKEN']
GITHUB_CLIENT_ID = ENV['GITHUB_CLIENT_ID']
GITHUB_CLIENT_SECRET = ENV['GITHUB_CLIENT_SECRET']
REPOSITORY_NAME = "rails/rails"
PER_PAGE = 100
TOTAL_PULL_REQUESTS_TO_BE_PROCESSED = 1000
RANGE_INFORMATION_LINE = /^@@ .+\+(?<line_number>\d+),/
MODIFIED_LINE = /^\+(?!\+|\+)/
REMOVED_LINE = /^[-]/
NOT_REMOVED_LINE = /^[^-]/
NO_NEWLINE_MESSAGE = /^\\ No newline at end of file$/

class GithubCrawler
  def client
    Octokit::Client.new(client_id: GITHUB_CLIENT_ID, client_secret: GITHUB_CLIENT_SECRET)
  end

  def pull_requests(pages)
    puts "Total number of pages: #{pages}"
    (1..pages).map do |page_no|
      client.pull_requests(REPOSITORY_NAME, { state: 'open', page: page_no, per_page: PER_PAGE })
    end
  rescue => e
    puts "Error retrieving pull requests information, more details: #{e.backtrace}"
  end

  def commits(pull_request)
    client.pull_request_commits(REPOSITORY_NAME, pull_request.number)
  rescue => e
    puts "Error retrieving pull request's commits information, more details: #{e.backtrace}"
  end

  def lines(patch)
    patch.lines
  end

  def changed_lines(patch)
    line_number = 0

    lines(patch).each_with_index.inject([]) do |lines, (content, patch_position)|
      case content
      when RANGE_INFORMATION_LINE
        line_number = Regexp.last_match[:line_number].to_i
      when NO_NEWLINE_MESSAGE
        # nop
      when MODIFIED_LINE
        line = {
          content: content,
          number: line_number,
          patch_position: patch_position
        }
        lines << line
        line_number += 1
      when NOT_REMOVED_LINE
        line_number += 1
      end

      lines
    end
  end

  def generate_pull_request_data(pr)
    pr_data = []
    commits(pr).each do |commit|
      individual_commit = client.commit(REPOSITORY_NAME, commit.sha)
      files = individual_commit[:files]
      files.each do |file|
        pr_data << {
          pull_request_link: pr.html_url,
          commit_sha: commit.sha,
          filename: file[:filename],
          blob_url: file[:blob_url],
          changed_lines: file[:patch].nil? ?  [] : changed_lines(file[:patch]),
        }
      end
    end

    {
      "#{pr.number}" => pr_data
    }
  end

  def group_prs_by_filename_and_changed_lines(pull_requets_data)
    pull_requets_data.flatten.map do |d|
      file_data = d[d.keys.first]
      grouped_files = file_data.group_by do |f|
        if f[:changed_lines].count > 0
          "#{f[:filename]}#L#{f[:changed_lines].map {|d| d[:number]}.flatten.uniq.join(',')}"
        else
          f[:filename]
        end
      end
      grouped_files.select { |k, v| v.count > 1 }
    end
  end

  def list_anamoly_prs_data
    puts "Github Repository: https://github.com/#{REPOSITORY_NAME}"
    prs = pull_requests(TOTAL_PULL_REQUESTS_TO_BE_PROCESSED/PER_PAGE).flatten.compact
    puts "Total number of pull requests to be processed: #{prs.count}"
    prs_info = prs.map do |pr|
      generate_pull_request_data(pr)
    end

    data = group_prs_by_filename_and_changed_lines(prs_info)
    final_prs_list = []
    data.delete_if &:empty?

    data.each do |d|
      d.each do |key,values|
        final_prs_list << values.map do |f|
          if f && f[:changed_lines].count > 0
            {
              "pull_request_link": f[:pull_request_link],
              "line_url": f[:blob_url] + "#L#{f[:changed_lines].map {|d| d[:number]}.flatten.uniq.join(',')}"
            }
          end
        end.flatten.compact
      end
    end

    puts final_prs_list.flatten.compact.count > 0 ? "Anamoly PRs: #{final_prs_list.flatten.compact}" : "There are no Anamoly PRs present in this repository"
  end
end

gc = GithubCrawler.new
gc.client
gc.list_anamoly_prs_data
