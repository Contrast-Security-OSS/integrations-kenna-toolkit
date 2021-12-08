# frozen_string_literal: true

require_relative "lib/checkmarx_sast_helper"
require "json"

module Kenna
  module Toolkit
    class CheckmarxSast < Kenna::Toolkit::BaseTask
      include Kenna::Toolkit::CheckmarxSastHelper

      def self.metadata
        {
          id: "checkmarx_sast",
          name: "checkmarx_sast Vulnerabilities",
          description: "Pulls assets and vulnerabilitiies from checkmarx_sast",
          options: [
            { name: "checkmarx_sast_console",
              type: "hostname",
              required: true,
              default: nil,
              description: "Your checkmarx_sast Console hostname (without protocol and port), e.g. app.checkmarx_sastsecurity.com" },
            { name: "checkmarx_sast_console_port",
              type: "integer",
              required: false,
              default: nil,
              description: "Your checkmarx_sast Console port, e.g. 8080" },
            { name: "checkmarx_sast_user",
              type: "user",
              required: true,
              default: nil,
              description: "checkmarx_sast Username" },
            { name: "checkmarx_sast_password",
              type: "password",
              required: true,
              default: nil,
              description: "checkmarx_sast Password" },
            { name: "client_id",
              type: "client detail",
              required: true,
              default: nil,
              description: "client id of checkmarx SAST" },
            { name: "client_secret",
              type: "client secret ",
              required: true,
              default: nil,
              description: "client secret of checkmarx SAST" },
            { name: "grant_type",
              type: "grant access type",
              required: false,
              default: "password",
              description: "grant access type" },
            { name: "scope",
              type: "api scope",
              required: false,
              default: "access_control_api sast_api",
              description: "scope API" },
            { name: "kenna_api_key",
              type: "api_key",
              required: false,
              default: nil,
              description: "Kenna API Key" },
            { name: "kenna_api_host",
              type: "hostname",
              required: false,
              default: "api.kennasecurity.com",
              description: "Kenna API Hostname" },
            { name: "kenna_connector_id",
              type: "integer",
              required: false,
              default: nil,
              description: "If set, we'll try to upload to this connector" },
            { name: "output_directory",
              type: "filename",
              required: false,
              default: "output/checkmarx_sast",
              description: "If set, will write a file upon completion. Path is relative to #{$basedir}" }
          ]
        }
      end

      def run(opts)
        super # opts -> @options

        initialze_options

        # Request checkmarx sast auth api to get access token
        token = request_checkmarx_sast_token
        fail_task "Unable to authenticate with checkmarx_sast, please check credentials" unless token

        # Request checkmarx sast api to fetch projects using token
        projects = fetch_checkmarx_sast_projects(token)

        projects.each do |project|
          print_good "Project Name: #{project['name']}"
          project_id = project["id"]

          # Request checkmarx sast api to fetch all scans of each project
          scan_results = fetch_all_scans_of_project(token, project_id)

          vuln_severity = { "High" => 9, "Medium" => 6, "Low" => 3, "Informational" => 0 }
          scan_results.each do |scan|
            report_id = generate_report_id_from_scan(token, scan["id"])
            sleep(10)
            scan_reports = fetch_scan_reports(token, report_id)
            
            scan_reports.values.each do |scan_report|
              application = scan_report.fetch("ProjectName")
              report_queries = scan_report.fetch("Query")
              report_queries.each do |query|
                report_results = query.fetch("Result")
                report_results.each do |result|
                  print result
                  if result.class == Hash
                    filename = result["Path"]["PathNode"]["FileName"] if result["Path"].present?
                    status = result["Status"] if result["Status"].present?
                    scanner_id = result["NodeId"]
                    severity = result["Severity"] if result["Severity"].present?
                    unique_identifier = query["QueryVersionCode"]
                    scanner_vulnerability = query["name"].to_s
                    vuln_title = query["cweId"].to_s + '-' + scanner_vulnerability
                    cwe = "CWE-#{query["cweId"]}"
                    found_date = DateTime.strptime(result["DetectionDate"],"%m/%d/%Y %k:%M:%S %p").strftime("%Y-%m-%d-%H:%M:%S") if result["DetectionDate"].present?
                    description = query["DeepLink"]

                    asset = {
                      "file" => filename,
                      "application" => application
                    }
                    asset.compact!

                    additional_fields = {
                      "Team" => scan_report.fetch("Team"),
                      "group" => query.fetch("group"),
                      "Language" => query.fetch("Language")
                    }
                    additional_fields.compact!

                    scanner_score = vuln_severity.fetch(severity)

                    # craft the vuln hash
                    finding = {
                      "scanner_identifier" => scanner_id,
                      "scanner_type" => "CheckmarxSast",
                      "created_at" => found_date,
                      "severity" => scanner_score,
                      "additional_fields" => additional_fields,
                      "vuln_def_name" => scanner_vulnerability
                    }

                    finding.compact!

                    vuln_def = {
                      "scanner_type" => "CheckmarxSast",
                      "name" => scanner_vulnerability,
                      "description" => description,
                      "cwe_identifiers" => cwe
                    }
                    vuln_def.compact!

                    # Create the KDI entries
                    create_kdi_asset_finding(asset, finding)
                    create_kdi_vuln_def(vuln_def)
                  end
                end
              end
            end
          end

          ### Write KDI format
          output_dir = "#{$basedir}/#{@options[:output_directory]}"
          filename = "checkmarx_sast_kdi_#{project_id}.json"
          kdi_upload output_dir, filename, @kenna_connector_id, @kenna_api_host, @kenna_api_key, false, @retries, @kdi_version
        end
        kdi_connector_kickoff @kenna_connector_id, @kenna_api_host, @kenna_api_key
      end

      def initialze_options
        @username = @options[:checkmarx_sast_user]
        @password = @options[:checkmarx_sast_password]
        @grant_type = @options[:grant_type]
        @scope = @options[:scope]
        @client_id = @options[:client_id]
        @client_secret = @options[:client_secret]
        @checkmarx_sast_url = if @options[:checkmarx_sast_console_port]
                                "#{@options[:checkmarx_sast_console]}:#{@options[:checkmarx_sast_console_port]}"
                              else
                                @options[:checkmarx_sast_console]
                              end
        @kenna_api_host = @options[:kenna_api_host]
        @kenna_api_key = @options[:kenna_api_key]
        @kenna_connector_id = @options[:kenna_connector_id]
        @retries = 3
        @kdi_version = 2
      end
    end
  end
end