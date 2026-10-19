package com.nest.app.academy.entity;

/** What an academy is asking the platform team for. */
public enum AcademyRequestType {
    /** Hand the academy to a new owner - the platform verifies and carries it out. */
    OWNERSHIP_TRANSFER,
    /** Move to another subscription plan. Approving it applies the plan. */
    PLAN_CHANGE,
    /** Stop the subscription at the end of the billing period. */
    CANCEL_SUBSCRIPTION,
    /** Close the academy. Approving only records the decision; suspending is still a deliberate step. */
    ACADEMY_CLOSURE,
    /** A plain message to the team. */
    SUPPORT
}
