package com.nest.app.fees.controller;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.nest.app.fees.dto.UpdateFeeTypeRequest;
import com.nest.app.fees.dto.UpdateOtherAmountRequest;
import com.nest.app.fees.entity.FeeMode;
import com.nest.app.fees.service.OtherFeesService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.MediaType;
import org.springframework.http.converter.json.MappingJackson2HttpMessageConverter;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.verify;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * The exact JSON the app sends to the two edit endpoints, bound the way Spring will bind it. The
 * service logic is tested elsewhere; this guards the wire format - an enum list for the payment
 * methods, an ISO date, a null date meaning "clear it" - which a unit test on the service cannot see.
 */
@ExtendWith(MockitoExtension.class)
class OtherFeesControllerWireTest {

    @Mock private OtherFeesService service;

    private MockMvc mvc;

    @BeforeEach
    void setUp() {
        mvc = MockMvcBuilders.standaloneSetup(new OtherFeesController(service))
                .setMessageConverters(new MappingJackson2HttpMessageConverter(new ObjectMapper().findAndRegisterModules()))
                .build();
    }

    @Test
    void editingAFeeTypeBindsMethodsDateAndBatches() throws Exception {
        UUID id = UUID.randomUUID();
        UUID batch = UUID.randomUUID();

        mvc.perform(put("/fees/other/types/" + id).contentType(MediaType.APPLICATION_JSON).content("""
                {"name":"Costume Fee","amount":900,"batchIds":["%s"],"dueDate":"2026-11-05",
                 "paymentMethods":["CASH","UPI"]}""".formatted(batch)))
                .andExpect(status().isOk());

        ArgumentCaptor<UpdateFeeTypeRequest> sent = ArgumentCaptor.forClass(UpdateFeeTypeRequest.class);
        verify(service).updateFeeType(org.mockito.ArgumentMatchers.eq(id), sent.capture());
        assertThat(sent.getValue().paymentMethods()).containsExactly(FeeMode.CASH, FeeMode.UPI);
        assertThat(sent.getValue().dueDate()).isEqualTo(LocalDate.of(2026, 11, 5));
        assertThat(sent.getValue().batchIds()).containsExactly(batch);
    }

    @Test
    void aNullDueDateArrivesAsNullSoItClearsTheDate() throws Exception {
        UUID id = UUID.randomUUID();

        mvc.perform(put("/fees/other/types/" + id).contentType(MediaType.APPLICATION_JSON).content("""
                {"name":"Costume Fee","amount":900,"batchIds":["%s"],"dueDate":null}""".formatted(UUID.randomUUID())))
                .andExpect(status().isOk());

        ArgumentCaptor<UpdateFeeTypeRequest> sent = ArgumentCaptor.forClass(UpdateFeeTypeRequest.class);
        verify(service).updateFeeType(org.mockito.ArgumentMatchers.eq(id), sent.capture());
        assertThat(sent.getValue().dueDate()).isNull();
    }

    @Test
    void aFeeTypeWithNoBatchesIsRejectedBeforeItReachesTheService() throws Exception {
        mvc.perform(put("/fees/other/types/" + UUID.randomUUID()).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"Costume Fee\",\"amount\":900,\"batchIds\":[]}"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void changingOneStudentsAmountBindsTheFeeTypeAndTheAmount() throws Exception {
        UUID student = UUID.randomUUID();
        UUID type = UUID.randomUUID();

        mvc.perform(patch("/fees/other/amount").contentType(MediaType.APPLICATION_JSON).content("""
                {"membershipId":"%s","feeTypeId":"%s","amount":500}""".formatted(student, type)))
                .andExpect(status().isOk());

        ArgumentCaptor<UpdateOtherAmountRequest> sent = ArgumentCaptor.forClass(UpdateOtherAmountRequest.class);
        verify(service).updateStudentAmount(sent.capture());
        assertThat(sent.getValue().membershipId()).isEqualTo(student);
        assertThat(sent.getValue().feeTypeId()).isEqualTo(type);
        assertThat(sent.getValue().studentFeeId()).isNull();
        assertThat(sent.getValue().amount()).isEqualByComparingTo("500");
    }

    @Test
    void anAmountOfZeroIsRejected() throws Exception {
        mvc.perform(patch("/fees/other/amount").contentType(MediaType.APPLICATION_JSON).content("""
                {"membershipId":"%s","feeTypeId":"%s","amount":0}""".formatted(UUID.randomUUID(), UUID.randomUUID())))
                .andExpect(status().isBadRequest());
    }
}
