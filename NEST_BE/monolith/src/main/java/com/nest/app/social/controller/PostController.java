package com.nest.app.social.controller;

import com.nest.app.social.dto.CreatePostRequest;
import com.nest.app.social.dto.MarkInterestRequest;
import com.nest.app.social.dto.PostResponse;
import com.nest.app.social.service.InterestService;
import com.nest.app.social.service.PostService;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

import java.util.List;
import java.util.UUID;

@RestController
@Tag(name = "Social")
public class PostController {

    private final PostService postService;
    private final InterestService interestService;

    public PostController(PostService postService, InterestService interestService) {
        this.postService = postService;
        this.interestService = interestService;
    }

    @PostMapping("/posts")
    public PostResponse create(@Valid @RequestBody CreatePostRequest request) {
        return postService.create(request);
    }

    @GetMapping("/feed")
    public List<PostResponse> feed() {
        return postService.publicFeed();
    }

    /** One person's posts across every identity they post under - "My Posts" (own userId) and
     * viewing someone else's profile from Search both call this, just with a different userId. */
    @GetMapping("/posts/by-user/{userId}")
    public List<PostResponse> byUser(@PathVariable UUID userId) {
        return postService.listByUser(userId);
    }

    /** Adds one image to an existing post - call once per image for a multi-photo post. */
    @PostMapping("/posts/{postId}/media")
    public PostResponse addMedia(@PathVariable UUID postId, @RequestParam("file") MultipartFile file) {
        return postService.attachMedia(postId, file);
    }

    @DeleteMapping("/posts/{postId}")
    public ResponseEntity<Void> delete(@PathVariable UUID postId) {
        postService.delete(postId);
        return ResponseEntity.noContent().build();
    }

    @PostMapping("/interests")
    public void markInterest(@Valid @RequestBody MarkInterestRequest request) {
        interestService.markInterest(request);
    }
}
