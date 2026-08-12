package com.camerae.eosrprobe;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;

import org.junit.Test;

public final class ExposureDurationPolicyTest {
    @Test
    public void supportsEveryWholeSecondFromOneThroughFortyFive() {
        assertEquals(1, ExposureDurationPolicy.clamp(0));
        assertEquals(1, ExposureDurationPolicy.clamp(1));
        assertEquals(27, ExposureDurationPolicy.clamp(27));
        assertEquals(45, ExposureDurationPolicy.clamp(45));
        assertEquals(45, ExposureDurationPolicy.clamp(60));
    }

    @Test
    public void displaysReferencesAtFiveSecondIntervals() {
        assertArrayEquals(
                new int[]{0, 5, 10, 15, 20, 25, 30, 35, 40, 45},
                ExposureDurationPolicy.referenceMarks()
        );
    }
}
