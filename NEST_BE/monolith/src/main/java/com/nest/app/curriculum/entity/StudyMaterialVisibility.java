package com.nest.app.curriculum.entity;

/**
 * Who inside a batch a material is for.
 *
 * <p>{@link #ALL} is the default and the overwhelming common case - a file shared with a class is
 * shared with the class. {@link #SELECTED} exists for the material that is genuinely for one or
 * two people: a correction for whoever missed a lesson, an exam piece assigned to one candidate.
 * Without it those can only be shared by sharing them with everybody.
 *
 * <p>This narrows within a batch; it never widens beyond one. A material still belongs to exactly
 * one batch, and naming a student outside it grants nothing.
 */
public enum StudyMaterialVisibility {
    ALL,
    SELECTED
}
