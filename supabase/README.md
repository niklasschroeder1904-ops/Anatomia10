# Anatomia online (Supabase)

Konten, Fortschritt-Abgleich zwischen Geräten, Freunde und Rangliste laufen über ein
Supabase-Projekt („Anatomia“, Region Frankfurt, kostenloser Tarif).

- `schema.sql`: Tabellen, Regeln (Row Level Security) und Funktionen der Datenbank.
  Eingespielt über die Management-API als Migration `anatomia_init`.
- Die App spricht den Server mit der Bibliothek `supabase.js` (supabase-js 2.118.0, MIT)
  an. Sie wird erst geladen, wenn jemand ein Konto benutzt.
- In `index.html` stehen die Adresse des Projekts und der **öffentliche** Schlüssel
  (`sb_publishable_…`). Der darf in der App stehen: Was ein Konto lesen und ändern darf,
  regeln die Datenbank-Regeln. Geheime Schlüssel (`sb_secret_…`) gehören nie in die App.

## Was gespeichert wird

| Tabelle | Inhalt | Wer darf lesen |
| --- | --- | --- |
| `profiles` | Spitzname, Freundescode | nur man selbst (Freunde sehen den Namen über die Rangliste) |
| `progress` | der ganze Lernfortschritt als JSON, mit Revision | nur man selbst |
| `friends` | Freundschaften (in beide Richtungen) | nur man selbst |

Funktionen: `add_friend(code)`, `remove_friend(id)`, `leaderboard(week_start, today)`
(Spitzname, XP gesamt, XP der Woche, Serie von mir und meinen Freunden), `delete_account()`.

## Abgleich

Jedes Gerät merkt sich den zuletzt mit dem Konto abgestimmten Stand. Beim Abgleich wird
zusammengeführt: XP und Taler addieren die Änderungen beider Geräte, Bestwerte behalten den
besseren, Listen (Käufe, Tage) behalten, was eine Seite hinzugefügt hat, bei einer
Karteikarte gilt die Wiederholung, die früher fällig ist. Ein neues Gerät ohne Fortschritt
übernimmt den Stand des Kontos; hat es eigenen Fortschritt, fragt die App einmal.

## Noch offen

- Bestätigungs- und Passwort-Mails brauchen einen eigenen Mail-Dienst (SMTP). Bis dahin ist
  die E-Mail-Bestätigung ausgeschaltet.
- Anmeldung mit Google (Google-Cloud-Projekt) und Apple (Apple-Entwicklerkonto).
- Tägliche Erinnerung per Push.
