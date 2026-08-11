package com.camerae.eosrprobe;

import android.app.Activity;
import android.os.Bundle;

/**
 * Placeholder activity for the standalone EOS R USB feasibility probe.
 *
 * The implementation intentionally starts in PLAN.md milestone M1 so that the
 * next development pass can keep hardware observations separate from guesses.
 */
public final class MainActivity extends Activity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);
    }
}
