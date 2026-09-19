export const DIALOGUE_COMMANDS = new Set([
  "propose_activity", "enroll_activity", "leave_activity", "cancel_activity", "contribute_route_repair", "send_message", "propose_trade", "counter_trade", "accept_trade", "reject_trade",
  "cancel_trade", "propose_cooperation", "counter_cooperation", "accept_cooperation",
  "public_food_plan", "public_wait", "reject_cooperation", "commit_contribution", "cancel_cooperation", "speak", "move", "rent_production", "offer_intelligence", "buy_intelligence", "share_intelligence", "propose_investigation", "accept_investigation", "cancel_investigation", "propose_joint_project", "accept_joint_project", "exit_joint_project", "propose_work", "counter_work", "accept_work", "cancel_work", "start_learning", "start_leisure", "manage_building", "propose_delivery", "cancel_delivery", "revise_project", "submit_project", "retry_project", "cancel_project", "publish_commission", "propose_player_commission", "claim_commission", "deliver_commission", "suggest_behavior",
]);

export const LOOP_DIALOGUE_COMMANDS = new Set([
  // Agree on a trip during dialogue; resolve fresh coordinates and move in
  // the next background Loop after the paused conversation ends.
  ...[...DIALOGUE_COMMANDS].filter(name=>name!=="move"),
  "resolve_relationship_dialogue", "propose_relationship", "respond_relationship", "end_relationship", "express_support", "request_supply", "wait", "adopt_short_term_goal", "revise_short_term_goal", "abandon_short_term_goal",
]);
