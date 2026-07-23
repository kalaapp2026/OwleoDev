package com.nest.common.security;

/**
 * Role hierarchy per PRD Section 2.1: Super Admin -> Academy Admin -> Trainer -> Student (ERP branch),
 * Artist | Guest (Social-only branch).
 */
public enum Role {
    SUPER_ADMIN,
    ACADEMY_ADMIN,
    TRAINER,
    STUDENT,
    ARTIST,
    GUEST
}
