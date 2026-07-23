package com.nest.app.social.controller;

import com.nest.app.social.dto.CreatePostRequest;
import com.nest.app.social.dto.MarkInterestRequest;
import com.nest.app.social.dto.PostResponse;
import com.nest.app.social.service.InterestService;
import com.nest.app.social.service.PostService;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

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

    @PostMapping("/interests")
    public void markInterest(@Valid @RequestBody MarkInterestRequest request) {
        interestService.markInterest(request);
    }
}
