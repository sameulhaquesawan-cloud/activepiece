#!/usr/bin/env bats

load helpers/common
load helpers/flow_code

@test "lead capture: a good lead is cleaned up" {
  run run_code lead-capture step_1 "{\"body\": $(cat "${OPSKIT_ROOT}/flows/lead-capture/test/good-lead.json"), \"defaultSource\": \"website\"}"
  [ "$status" -eq 0 ]
  [ "$(jq -r .email <<< "$output")" = "jane@example.com" ]
  [ "$(jq -r .name <<< "$output")" = "Jane Example" ]
  [ "$(jq -r .source <<< "$output")" = "contact form" ]
  [ "$(jq -r .label <<< "$output")" = "Jane Example" ]
  [[ "$(jq -r .receivedAt <<< "$output")" == 20*Z ]]
}

@test "lead capture: missing name and source fall back; long text is cut" {
  run run_code lead-capture step_1 "{\"body\": {\"email\": \" A@Example.com \", \"message\": \"$(printf 'x%.0s' {1..6000})\"}, \"defaultSource\": \"website\"}"
  [ "$status" -eq 0 ]
  [ "$(jq -r .email <<< "$output")" = "a@example.com" ]
  [ "$(jq -r .name <<< "$output")" = "" ]
  [ "$(jq -r .greetingName <<< "$output")" = "there" ]
  [ "$(jq -r .label <<< "$output")" = "a@example.com" ]
  [ "$(jq -r .source <<< "$output")" = "website" ]
  [ "$(jq -r '.message | length' <<< "$output")" = "5000" ]
}

@test "lead capture: an invalid or missing email fails without quoting the lead" {
  run run_code lead-capture step_1 "{\"body\": $(cat "${OPSKIT_ROOT}/flows/lead-capture/test/bad-email.json"), \"defaultSource\": \"website\"}"
  [ "$status" -eq 3 ]
  [ "$output" = 'THROWN: Invalid email in field "email" - lead not saved' ]
  run run_code lead-capture step_1 '{"body": {}, "defaultSource": "website"}'
  [ "$status" -eq 3 ]
}

invoice_rows() {
  jq -nc --slurpfile rows "${OPSKIT_ROOT}/flows/invoice-reminder/test/$1" '{rows: $rows[0], overdueDays: 3, repeatDays: 7}'
}

@test "invoice reminder: only the open, overdue, not recently reminded invoice is picked" {
  run run_code invoice-reminder step_2 "$(invoice_rows rows.json)"
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.due[].invoice]' <<< "$output")" = '["INV-1001"]' ]
  [ "$(jq -c '.due[0] | {row, email, customer, amount, dueDate}' <<< "$output")" = '{"row":2,"email":"sam@example.com","customer":"Sam Example","amount":"€120.00","dueDate":"2026-01-10"}' ]
  [ "$(jq -c .problems <<< "$output")" = '[]' ]
  [ "$(jq -r .count <<< "$output")" = "1" ]
}

@test "invoice reminder: rows with a broken email are reported, the rest still reminded" {
  run run_code invoice-reminder step_2 "$(invoice_rows rows-bad-email.json)"
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.due[].invoice]' <<< "$output")" = '["INV-1001"]' ]
  [ "$(jq -c .problems <<< "$output")" = '[6]' ]
  run run_code invoice-reminder step_6 '{"problems": [6, 9], "count": 1}'
  [ "$status" -eq 3 ]
  [ "$output" = "THROWN: 2 invoice row(s) skipped - invalid email or due date in sheet rows 6, 9" ]
  run run_code invoice-reminder step_6 '{"problems": [], "count": 1}'
  [ "$status" -eq 0 ]
}

@test "invoice reminder: header names are matched loosely and a {rows: […]} shape is accepted" {
  run run_code invoice-reminder step_2 '{"rows": {"rows": [{"row": 7, "values": {" invoice ": "A-1", "EMAIL": "a@example.com", "Due Date": "2020-01-01", "STATUS": "Open"}}]}, "overdueDays": "0", "repeatDays": "7"}'
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.due[] | [.row, .invoice, .customer]]' <<< "$output")" = '[[7,"A-1","there"]]' ]
}

review_order() {
  jq -nc --slurpfile body "${OPSKIT_ROOT}/flows/review-request/test/$1" '{body: $body[0]}'
}

@test "review request: Shopify, WooCommerce and Stripe orders are read" {
  run run_code review-request step_1 "$(review_order shopify-paid.json)"
  [ "$status" -eq 0 ]
  [ "$(jq -c '{email, firstName, paid}' <<< "$output")" = '{"email":"jane@example.com","firstName":"Jane","paid":true}' ]
  run run_code review-request step_1 "$(review_order woo-pending.json)"
  [ "$status" -eq 0 ]
  [ "$(jq -c '{orderId, email, paid, status}' <<< "$output")" = '{"orderId":"727","email":"sam@example.com","paid":false,"status":"pending"}' ]
  run run_code review-request step_1 '{"body": {"data": {"object": {"id": "cs_1", "payment_status": "paid", "customer_details": {"email": "a@example.com", "name": "Ann Example"}}}}}'
  [ "$status" -eq 0 ]
  [ "$(jq -c '{orderId, email, firstName, paid}' <<< "$output")" = '{"orderId":"cs_1","email":"a@example.com","firstName":"Ann","paid":true}' ]
}

@test "review request: a paid order without email or an order without id fails" {
  run run_code review-request step_1 "$(review_order stripe-no-email.json)"
  [ "$status" -eq 3 ]
  [ "$output" = "THROWN: Paid order cs_test_example has no valid customer email" ]
  run run_code review-request step_1 '{"body": {"email": "a@example.com"}}'
  [ "$status" -eq 3 ]
  [ "$output" = "THROWN: Order webhook without an order id" ]
}

@test "review request: an order is asked once and unpaid orders never" {
  run run_code review-request step_3 '{"seen": null, "paid": true}'
  [ "$(jq -c . <<< "$output")" = '{"send":true,"duplicate":false}' ]
  run run_code review-request step_3 '{"seen": "jane@example.com", "paid": true}'
  [ "$(jq -c . <<< "$output")" = '{"send":false,"duplicate":true}' ]
  run run_code review-request step_3 '{"seen": "", "paid": false}'
  [ "$(jq -r .send <<< "$output")" = "false" ]
}
