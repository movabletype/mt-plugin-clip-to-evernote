package ClipToEvernote;
use strict;
use warnings;
use Encode;
use MT;
use MT::Entry;
use ClipToEvernote::Client;

sub insert_widget {
    my ( $cb, $app, $param, $tmpl ) = @_;
    my $html = <<'HTML';
<script type="text/javascript">
function reload_evernote_widget (options) {
  options = jQuery.extend({}, options);
  var $box = jQuery('div#post-to-evernote div.widget-content');
  $box.html('<img src="<mt:var name="static_uri">images/indicator.white.gif" />');
  var url = '<mt:var name="evernote_widget_url">';
  if ( options.signout ) {
    url += '&signout=1';
  }
  jQuery.get(url, function (data) {
      // Test if it's MT's error screen
      var $error = jQuery('<div />').html(data).find('#generic-error');
      if ( $error.length ) {
        data = $error;
      }
      $box.html(data).find('a.mt-open-dialog').mtDialog();
  });
}

jQuery( function () {
  reload_evernote_widget();
});

jQuery('.signout-evernote').live( 'click', function () {
console.log('so');
  reload_evernote_widget({ signout: 1 });
  return false;
});

</script>
<mt:var name="evernote_widget_url">
HTML
    $param->{evernote_widget_url} = $app->uri(
        mode => 'evernote_widget',
        args => {
            entry_id => $app->param('id') || 0,
            blog_id  => $app->param('blog_id'),
        },
    );
    my $beacon = $tmpl->getElementById("entry-feedback-widget");
    my $widget = $tmpl->createElement('app:widget', {
        id       => 'post-to-evernote',
        label    => 'Evernote',
        engry_id => $app->param('id'),
    });
    $widget->innerHTML($html);
    $tmpl->insertBefore( $widget, $beacon );
    return 1;
}

sub post_to_evernote {
    my ( $cb, $app, $entry, $orig ) = @_;
    my $plugin = MT->component('cliptoevernote');
    my $notebook_guid = $app->param('destination-notebook');
    my $ever = ClipToEvernote::Client->new($app)
        or return 1;
    if ( $notebook_guid ) {
        my $result = $ever->entry2note( $entry, $notebook_guid );
        if ( !$result ) {
            return $cb->error($plugin->translate('Failed to sync entry to Evernote.'));
        }
        my $guid = $result->{guid};
        $entry->evernote_note_guid($guid);
        $entry->save;
    }
    else {
        if ( $orig && ( my $guid = $orig->evernote_note_guid) ) {
            $ever->proc('deleteNote', $guid)
                or return $cb->error($plugin->translate('Failed to sync entry to Evernote.'));
        }
        $entry->evernote_note_guid(0);
        $entry->save;
    }
    return 1;
}

1;
