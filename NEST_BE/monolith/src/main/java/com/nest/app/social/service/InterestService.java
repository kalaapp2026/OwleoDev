package com.nest.app.social.service;

import com.nest.app.event.repository.EventRepository;
import com.nest.app.social.dto.MarkInterestRequest;
import com.nest.app.social.entity.Interest;
import com.nest.app.social.repository.InterestRepository;
import com.nest.common.audit.Auditable;
import com.nest.common.exception.BadRequestException;
import com.nest.common.security.TenantContext;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** "Mark Interest" (PRD 3.13) - available to Guests and Students; schedules a reminder
 * notification in notification-service once that module exists (Phase 4). */
@Service
public class InterestService {

    private final InterestRepository interestRepository;
    private final EventRepository eventRepository;

    public InterestService(InterestRepository interestRepository, EventRepository eventRepository) {
        this.interestRepository = interestRepository;
        this.eventRepository = eventRepository;
    }

    /** Withdraws interest. Always allowed - the deadline only stops NEW interest. */
    @Transactional
    public void removeEventInterest(java.util.UUID eventId) {
        interestRepository.deleteByUserIdAndEventId(TenantContext.currentUserId(), eventId);
    }

    @Transactional
    @Auditable(action = "INTEREST_MARKED", entityType = "interest")
    public void markInterest(MarkInterestRequest request) {
        boolean hasEvent = request.eventId() != null;
        boolean hasPost = request.postId() != null;
        if (hasEvent == hasPost) {
            throw new BadRequestException("Exactly one of eventId or postId must be set");
        }

        var userId = TenantContext.currentUserId();
        if (hasEvent) {
            var event = eventRepository.findById(request.eventId()).orElse(null);
            if (event != null && event.getInterestDeadline() != null
                    && java.time.LocalDate.now().isAfter(event.getInterestDeadline())
                    && !interestRepository.existsByUserIdAndEventId(userId, request.eventId())) {
                throw new BadRequestException("Interest for this event closed on " + event.getInterestDeadline());
            }
        }
        if (hasEvent && interestRepository.existsByUserIdAndEventId(userId, request.eventId())) {
            return;
        }
        if (hasPost && interestRepository.existsByUserIdAndPostId(userId, request.postId())) {
            return;
        }

        interestRepository.save(Interest.builder()
                .userId(userId)
                .eventId(request.eventId())
                .postId(request.postId())
                .build());
    }
}
