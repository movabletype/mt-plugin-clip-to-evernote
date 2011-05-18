package ClipToEvernote::L10N::ja;

use strict;

use base 'ClipToEvernote::L10N';
use vars qw( %Lexicon );
%Lexicon = (
## plugins/ClipToEvernote/lib/ClipToEvernote.pm
  'Evernote' => 'Evernote',
  q{Evernote access is allowed only for entry's owner.} => q{ブログ記事の所有者以外はEvernoteへのアクセスは出来ません。},
  'Failed to sync entry to Evernote.' => 'Evernoteとの同期に失敗しました。',

## plugins/ClipToEvernote/tmpl/evernote_widget.tmpl
  'Do not clip' => 'クリップしない',
  'Sign Out' => 'サインアウト',
  'Sign in to Evernote' => 'Evernoteにサインイン',
  'View in Evernote' => 'Evernoteでブログ記事を見る',

## plugins/ClipToEvernote/tmpl/system.tmpl
  'Consumer Key' => 'Consumer Key',
  'Consumer Secret' => 'Consumer Secret',
);

1;
