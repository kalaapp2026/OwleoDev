package com.nest.app.selfservice.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.util.UUID;

/** A student saying "I'd like to join this course" - a signal the academy can act on, not an
 * enrolment. Enrolment stays an admin action. */
@Entity
@Table(name = "course_interests")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class CourseInterest {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "academy_id", nullable = false)
    private UUID academyId;

    @Column(name = "course_id", nullable = false)
    private UUID courseId;

    @Column(name = "membership_id", nullable = false)
    private UUID membershipId;
}
