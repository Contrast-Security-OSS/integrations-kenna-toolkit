# frozen_string_literal: true

require "json"
require "active_support"
require "active_support/core_ext"
require "rest_client"
require "base64"

module Kenna
  module Toolkit
    module QualysWasHelper
      def qualys_was_get_token(username, password)
        auth_details = "#{username}:#{password}"
        Base64.encode64(auth_details)
      end

      def qualys_was_get_webapp(token, qualys_was_url = "qualysapi.qg3.apps.qualys.com/qps/rest/3.0/")
        print_good "Getting Webapp \n"
        qualys_was_auth_api = "https://#{qualys_was_url}search/was/webapp"

        @headers = {
          "Content-Type" => "application/json",
          "accept" => "application/json",
          "Authorization" => "Basic #{token}"
        }

        response = []
        next_page = true
        last_id = nil
        page = 1

        while next_page
          print_good "Fetching Next webapp" if page > 1
          page += 1

          payload = {
            "ServiceRequest" => {
              "preferences" => {
                "verbose" => "true",
                "limitResults" => "100"
              }
            }
          }.compare_by_identity

          if last_id.present?
            payload["ServiceRequest"]["filters"] = {
              "Criteria" => {
                "field" => "id",
                "operator" => "GREATER",
                "value" => last_id.to_s
              }
            }
          end

          auth_response = http_post(qualys_was_auth_api, @headers, payload.to_json)
          return nil unless auth_response

          begin
            res_new = JSON.parse(auth_response.body)
            auth_response = nil
            if res_new["ServiceResponse"]["hasMoreRecords"] == "true"
              last_id = res_new["ServiceResponse"]["lastId"]
            else
              next_page = false
            end
            response << res_new
          rescue JSON::ParserError
            print_error "Unable to process Auth Token response!"
          end
        end
        print_good response
        print_good "\n\n \n\n"
        response.flatten
      end

      def qualys_was_get_webapp_findings(webapp_id, token, qualys_was_url = "qualysapi.qg3.apps.qualys.com/qps/rest/3.0/")
        print_good "Getting Webapp Findings For #{webapp_id} \n"
        qualys_was_auth_api = "https://#{qualys_was_url}search/was/finding"

        @headers = {
          "Content-Type" => "application/json",
          "accept" => "application/json",
          "Authorization" => "Basic #{token}"
        }

        response = []
        next_page = true
        last_id = nil
        page = 1
        while next_page
          print_good "Fetching Next Page For #{webapp_id}" if page > 1
          page += 1
          payload = {
            "ServiceRequest": {
              "preferences": {
                "verbose": "true",
                "limitResults": "100" # TODO: optional
              },
              "filters": {
                "Criteria": {
                  "field": "webApp.id",
                  "operator": "EQUALS",
                  "value": webapp_id.to_s
                }
              }
            }
          }.compare_by_identity

          if last_id.present?
            payload[:ServiceRequest][:filters]["Criteria"] = {
              "field": "id",
              "operator": "GREATER",
              "value": last_id.to_s
            }
          end

          auth_response = http_post(qualys_was_auth_api, @headers, payload.to_json)
          return nil unless auth_response

          begin
            res = JSON.parse(auth_response.body)
            if res["ServiceResponse"]["hasMoreRecords"] == "true"
              last_id = res["ServiceResponse"]["lastId"]
            else
              next_page = false
            end
            response << res
          rescue JSON::ParserError
            print_error "Unable to process Auth Token response!"
          end

          print_good response
          print_good "\n\n \n\n"
        end

        response.flatten
      end

      def qualys_was_get_vuln(qids, token, qualys_was_url = "qualysapi.qg3.apps.qualys.com/api/2.0/fo/")
        print_good "Getting VULN For #{qids} \n"
        qualys_was_auth_api = URI("https://#{qualys_was_url}knowledge_base/vuln/")

        @headers = {
          "Content-Type" => "application/json",
          "accept" => "application/json",
          "Authorization" => "Basic #{token}",
          "X-Requested-With" => "QualysPostman"
        }

        payload = {
          "action" => "list",
          "ids" => qids.join(",")
        }

        qualys_was_auth_api.query = URI.encode_www_form(payload)
        auth_response = http_get(qualys_was_auth_api.to_s, @headers)
        return nil unless auth_response

        begin
          response = Hash.from_xml(auth_response.body).to_json
        rescue JSON::ParserError
          print_error "Unable to process XML response!"
        end

        print_good response
        print_good "\n\n \n\n"
        response
      end
    end
  end
end