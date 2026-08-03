package com.nest.app.identity.repository;

import org.junit.jupiter.api.Test;
import org.springframework.data.jpa.repository.Modifying;

import java.io.IOException;
import java.lang.reflect.Method;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.stream.Stream;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Guards against a bug that shipped and lost data silently: a {@code @Modifying} query declared
 * {@code clearAutomatically = true} without {@code flushAutomatically = true}.
 *
 * <p>Spring Data does NOT flush before a modifying query by default. {@code clearAutomatically}
 * then detaches everything in the persistence context - so any entity a caller saved earlier in
 * the same transaction, but which hadn't been flushed yet, had its INSERT thrown away. Trainer
 * registration did exactly that: it saved the User and AcademyMembership, then mapped courses
 * (whose bulk delete cleared the context). The endpoint returned 200 with a username and
 * temporary password for an account that was never written, and the person could not log in.
 *
 * <p>Nothing about that is visible to a Mockito test - the repository is a mock, so the
 * persistence context never exists. Rather than require a live database for one annotation, this
 * asserts the contract directly across every repository, including ones added later.
 *
 * <p>What this does NOT prove: that any given query is correct, or that clearing is the right
 * choice at all. Only that the two flags are never separated, which is the specific mistake made.
 */
class ModifyingQueryFlushContractTest {

    @Test
    void everyClearAutomaticallyQueryAlsoFlushes() throws Exception {
        List<String> offenders = new ArrayList<>();

        for (Class<?> repository : repositoryInterfaces()) {
            for (Method method : repository.getDeclaredMethods()) {
                Modifying modifying = method.getAnnotation(Modifying.class);
                if (modifying == null) {
                    continue;
                }
                if (modifying.clearAutomatically() && !modifying.flushAutomatically()) {
                    offenders.add(repository.getSimpleName() + "." + method.getName() + "()");
                }
            }
        }

        assertThat(offenders)
                .as("""
                        @Modifying(clearAutomatically = true) without flushAutomatically = true \
                        discards un-flushed inserts from the same transaction - the caller gets a \
                        success response for data that was never written. Add \
                        flushAutomatically = true to: %s""", offenders)
                .isEmpty();
    }

    /** Loads every compiled *Repository interface under com.nest.app from the build output, so a
     * repository added in future is covered without anyone remembering to update this test. */
    private List<Class<?>> repositoryInterfaces() throws IOException {
        Path classesRoot = Path.of("target", "classes");
        assertThat(classesRoot)
                .as("compiled classes must exist for this test to inspect anything")
                .exists();

        List<Class<?>> found = new ArrayList<>();
        try (Stream<Path> paths = Files.walk(classesRoot)) {
            for (Path path : paths.filter(p -> p.getFileName().toString().endsWith("Repository.class")).toList()) {
                String className = classesRoot.relativize(path).toString()
                        .replace(".class", "")
                        .replace('\\', '.')
                        .replace('/', '.');
                try {
                    Class<?> loaded = Class.forName(className);
                    if (loaded.isInterface()) {
                        found.add(loaded);
                    }
                } catch (ClassNotFoundException | NoClassDefFoundError ignored) {
                    // Not loadable in the test classpath - nothing this test can assert about it.
                }
            }
        }

        assertThat(found).as("should have discovered the app's repositories").isNotEmpty();
        return found;
    }
}
