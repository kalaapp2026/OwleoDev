package com.nest.app.curriculum.service;

import com.nest.app.curriculum.dto.PlaylistResponse;
import com.nest.app.curriculum.dto.StudyMaterialResponse;
import com.nest.app.curriculum.entity.MaterialPlaylist;
import com.nest.app.curriculum.entity.MaterialPlaylistEntry;
import com.nest.app.curriculum.entity.StudyMaterialPermission;
import com.nest.app.curriculum.entity.StudyMaterialType;
import com.nest.app.curriculum.entity.StudyMaterialVisibility;
import com.nest.app.curriculum.repository.MaterialPlaylistEntryRepository;
import com.nest.app.curriculum.repository.MaterialPlaylistRepository;
import com.nest.common.exception.BadRequestException;
import com.nest.common.exception.ForbiddenException;
import com.nest.common.security.MembershipClaim;
import com.nest.common.security.NestPrincipal;
import com.nest.common.security.Role;
import com.nest.common.security.TenantContext;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Covers the ordering rules, which are where this service can actually be wrong.
 *
 * <p>An order is not something the user can sanity-check at a glance on a long playlist, so a
 * reorder that quietly drops or duplicates a row would go unnoticed until a class ran in the wrong
 * sequence.
 */
@ExtendWith(MockitoExtension.class)
class MaterialPlaylistServiceTest {

    @Mock
    private MaterialPlaylistRepository playlistRepository;
    @Mock
    private MaterialPlaylistEntryRepository entryRepository;
    @Mock
    private StudyMaterialService studyMaterialService;

    private MaterialPlaylistService service;

    private final UUID academyId = UUID.randomUUID();
    private final UUID membershipId = UUID.randomUUID();
    private final UUID playlistId = UUID.randomUUID();

    @BeforeEach
    void setUp() {
        service = new MaterialPlaylistService(playlistRepository, entryRepository, studyMaterialService);

        MembershipClaim claim = new MembershipClaim(
                membershipId, academyId, "Natyalaya", Role.TRAINER, Set.of(), Set.of());
        TenantContext.set(new NestPrincipal(
                UUID.randomUUID(), "meera", Role.TRAINER, List.of(claim), membershipId));
    }

    @AfterEach
    void tearDown() {
        TenantContext.clear();
    }

    private MaterialPlaylist playlist() {
        return MaterialPlaylist.builder()
                .id(playlistId)
                .membershipId(membershipId)
                .academyId(academyId)
                .name("Warm-ups")
                .createdAt(Instant.now())
                .build();
    }

    private MaterialPlaylistEntry entry(UUID id, UUID materialId, int position) {
        return MaterialPlaylistEntry.builder()
                .id(id).playlistId(playlistId).materialId(materialId).position(position).build();
    }

    private StudyMaterialResponse material(UUID id) {
        return new StudyMaterialResponse(id, UUID.randomUUID(), "Track", null,
                "/uploads/t.mp3", "t.mp3", "audio/mpeg", StudyMaterialType.AUDIO, 100,
                StudyMaterialPermission.VIEW_ONLY, StudyMaterialVisibility.ALL, Set.of(),
                UUID.randomUUID(), "Meera", Instant.now());
    }

    /** Wires the reads that every path through get() performs. */
    private List<MaterialPlaylistEntry> stubEntries(MaterialPlaylistEntry... entries) {
        List<MaterialPlaylistEntry> list = new ArrayList<>(List.of(entries));
        lenient().when(playlistRepository.findById(playlistId)).thenReturn(Optional.of(playlist()));
        lenient().when(entryRepository.findByPlaylistIdOrderByPositionAsc(playlistId))
                .thenReturn(list);
        lenient().when(studyMaterialService.byIds(anyList())).thenAnswer(inv -> {
            List<UUID> ids = inv.getArgument(0);
            return ids.stream().map(this::material).toList();
        });
        return list;
    }

    @Test
    void reorderRenumbersFromZeroInTheOrderGiven() {
        UUID a = UUID.randomUUID();
        UUID b = UUID.randomUUID();
        UUID c = UUID.randomUUID();
        List<MaterialPlaylistEntry> entries = stubEntries(
                entry(a, UUID.randomUUID(), 0),
                entry(b, UUID.randomUUID(), 1),
                entry(c, UUID.randomUUID(), 2));

        service.reorder(playlistId, List.of(c, a, b));

        // Positions are rewritten as a dense 0..n-1 run rather than patched, so no gaps or ties
        // can accumulate into an order that depends on insertion.
        assertThat(entries.stream().filter(e -> e.getId().equals(c)).findFirst().get().getPosition())
                .isZero();
        assertThat(entries.stream().filter(e -> e.getId().equals(a)).findFirst().get().getPosition())
                .isEqualTo(1);
        assertThat(entries.stream().filter(e -> e.getId().equals(b)).findFirst().get().getPosition())
                .isEqualTo(2);
    }

    @Test
    void reorderKeepsAnEntryTheClientForgotToMention() {
        UUID a = UUID.randomUUID();
        UUID b = UUID.randomUUID();
        List<MaterialPlaylistEntry> entries = stubEntries(
                entry(a, UUID.randomUUID(), 0),
                entry(b, UUID.randomUUID(), 1));

        // A stale client sends only what it knew about. Dropping the rest would silently delete
        // songs on a reorder, which is far worse than putting them at the end.
        service.reorder(playlistId, List.of(b));

        assertThat(entries.stream().filter(e -> e.getId().equals(b)).findFirst().get().getPosition())
                .isZero();
        assertThat(entries.stream().filter(e -> e.getId().equals(a)).findFirst().get().getPosition())
                .isEqualTo(1);
    }

    @Test
    void reorderIgnoresAnEntryIdTheServerNoLongerHas() {
        UUID a = UUID.randomUUID();
        List<MaterialPlaylistEntry> entries = stubEntries(entry(a, UUID.randomUUID(), 0));

        // Removed in another tab. Rejecting the whole reorder over it would lose a real edit.
        service.reorder(playlistId, List.of(UUID.randomUUID(), a));

        assertThat(entries.get(0).getPosition()).isZero();
    }

    @Test
    void addingTheSameMaterialTwiceCreatesTwoEntries() {
        UUID materialId = UUID.randomUUID();
        stubEntries();

        service.addMaterials(playlistId, List.of(materialId, materialId));

        // Playing a piece twice - slowly, then up to tempo - is the whole reason entries carry
        // their own ids instead of being keyed by material.
        verify(entryRepository, org.mockito.Mockito.times(2)).save(any(MaterialPlaylistEntry.class));
    }

    @Test
    void addingChecksTheCallerMaySeeTheMaterial() {
        UUID materialId = UUID.randomUUID();
        stubEntries();
        org.mockito.Mockito.doThrow(new ForbiddenException("nope"))
                .when(studyMaterialService).assertReadable(materialId);

        assertThatThrownBy(() -> service.addMaterials(playlistId, List.of(materialId)))
                .isInstanceOf(ForbiddenException.class);

        // A playlist must not become a way to reach a file the caller was never shared.
        verify(entryRepository, never()).save(any(MaterialPlaylistEntry.class));
    }

    @Test
    void anotherMembershipsPlaylistIsNotReadable() {
        MaterialPlaylist someoneElses = playlist();
        someoneElses.setMembershipId(UUID.randomUUID());
        when(playlistRepository.findById(playlistId)).thenReturn(Optional.of(someoneElses));

        assertThatThrownBy(() -> service.get(playlistId))
                .isInstanceOf(ForbiddenException.class);
    }

    @Test
    void aBlankNameIsRejected() {
        assertThatThrownBy(() -> service.create("   "))
                .isInstanceOf(BadRequestException.class);
        verify(playlistRepository, never()).save(any(MaterialPlaylist.class));
    }

    @Test
    void duplicateInsertsTheCopyDirectlyBelowItsOriginal() {
        UUID a = UUID.randomUUID();
        UUID b = UUID.randomUUID();
        UUID materialId = UUID.randomUUID();
        MaterialPlaylistEntry first = entry(a, materialId, 0);
        MaterialPlaylistEntry second = entry(b, UUID.randomUUID(), 1);
        stubEntries(first, second);
        when(entryRepository.findById(a)).thenReturn(Optional.of(first));

        service.duplicateEntry(playlistId, a);

        // The row after it shifts down to make room, so the copy lands adjacent rather than at
        // the end where it would read as unrelated to the original.
        assertThat(second.getPosition()).isEqualTo(2);
    }
}
