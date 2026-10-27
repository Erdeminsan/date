-- Cover referencing keys used when accounts are deleted or moderator IDs nulled.
-- These do not grant access or change cascade behavior.
create index account_sanctions_lifted_by_idx on app_private.account_sanctions(lifted_by);
create index account_sanctions_moderator_idx on app_private.account_sanctions(moderator_id);
create index account_sanctions_reporter_idx on app_private.account_sanctions(reporter_id);
create index game_input_packets_player_idx on app_private.game_input_packets(player_id);
create index game_results_winner_idx on app_private.game_results(winner_id);
create index report_reviews_reviewer_idx on app_private.report_reviews(reviewer_id);
create index sanction_appeals_reviewer_idx on app_private.sanction_appeals(reviewer_id);
