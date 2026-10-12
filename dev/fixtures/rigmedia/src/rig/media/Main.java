package rig.media;

import android.app.Activity;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.media.MediaMetadata;
import android.media.session.MediaSession;
import android.media.session.PlaybackState;
import android.os.Bundle;
import android.os.SystemClock;
import android.widget.TextView;

public class Main extends Activity {
  MediaSession session;
  long position = 0;
  int state = PlaybackState.STATE_PLAYING;
  int track = 1;

  void publish() {
    PlaybackState.Builder b = new PlaybackState.Builder()
      .setActions(PlaybackState.ACTION_PLAY | PlaybackState.ACTION_PAUSE | PlaybackState.ACTION_PLAY_PAUSE
        | PlaybackState.ACTION_SKIP_TO_NEXT | PlaybackState.ACTION_SKIP_TO_PREVIOUS | PlaybackState.ACTION_SEEK_TO)
      .setState(state, position, state == PlaybackState.STATE_PLAYING ? 1f : 0f, SystemClock.elapsedRealtime());
    session.setPlaybackState(b.build());
    session.setMetadata(new MediaMetadata.Builder()
      .putString(MediaMetadata.METADATA_KEY_TITLE, "Rig Track " + track)
      .putString(MediaMetadata.METADATA_KEY_ARTIST, "Rig Artist")
      .putString(MediaMetadata.METADATA_KEY_ALBUM, "Rig Album")
      .putLong(MediaMetadata.METADATA_KEY_DURATION, 600000).build());
  }

  @Override protected void onCreate(Bundle s) {
    super.onCreate(s);
    TextView t = new TextView(this);
    t.setText("Rig player: holds a media session for the plugin's soak");
    setContentView(t);
    session = new MediaSession(this, "rig");
    session.setCallback(new MediaSession.Callback() {
      @Override public void onPlay() { state = PlaybackState.STATE_PLAYING; publish(); }
      @Override public void onPause() { state = PlaybackState.STATE_PAUSED; publish(); }
      @Override public void onSkipToNext() { track++; position = 0; publish(); }
      @Override public void onSkipToPrevious() { track = Math.max(1, track - 1); position = 0; publish(); }
      @Override public void onSeekTo(long p) { position = p; publish(); }
    });
    session.setActive(true);
    publish();
    registerReceiver(new BroadcastReceiver() {
      @Override public void onReceive(Context c, Intent i) {
        String a = i.getAction();
        if (a.endsWith("PLAY")) state = PlaybackState.STATE_PLAYING;
        else if (a.endsWith("PAUSE")) state = PlaybackState.STATE_PAUSED;
        else if (a.endsWith("NEXT")) { track++; position = 0; }
        else if (a.endsWith("STOP")) { session.setActive(false); return; }
        else if (a.endsWith("START")) session.setActive(true);
        publish();
      }
    }, new IntentFilter() {{ for (String a : new String[]{"PLAY","PAUSE","NEXT","STOP","START"}) addAction("rig.media." + a); }},
      Context.RECEIVER_EXPORTED);
  }
}
