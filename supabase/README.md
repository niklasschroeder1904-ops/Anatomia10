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
| `profiles` | Spitzname, Freundescode, Gruppe (`grp`), in der weltweiten Rangliste zeigen (`public`) | nur man selbst (andere sehen den Namen über die Ranglisten) |
| `progress` | der ganze Lernfortschritt als JSON, mit Revision | nur man selbst |
| `friends` | Freundschaften (in beide Richtungen) | nur man selbst |
| `stats` | XP gesamt, XP der Woche, Serie – bei jedem Abgleich aus dem Fortschritt berechnet | niemand direkt, nur über die Ranglisten |

Funktionen: `add_friend(code)`, `remove_friend(id)`, `leaderboard(week_start, today)`
(Spitzname, XP gesamt, XP der Woche, Serie von mir und meinen Freunden),
`global_board(period, lim)` (weltweite Rangliste: wie viele dabei sind, mein Platz, die ersten 50;
Woche ab Montag nach deutscher Zeit), `group_board(period)` (die Gruppen – Medizinstudium,
Ärztinnen & Ärzte, Zahnmedizin, Pflege, Physiotherapie, Rettungsdienst, andere Gesundheitsberufe,
Selbststudium – nach XP pro Person, die gelernt hat; dazu mein Platz in meiner Gruppe),
`delete_account()`. Wer `profiles.public` ausschaltet, steht
nicht in der Liste der anderen, sieht aber den eigenen Platz.

## Abgleich

Jedes Gerät merkt sich den zuletzt mit dem Konto abgestimmten Stand. Beim Abgleich wird
zusammengeführt: XP und Taler addieren die Änderungen beider Geräte, Bestwerte behalten den
besseren, Listen (Käufe, Tage) behalten, was eine Seite hinzugefügt hat, bei einer
Karteikarte gilt die Wiederholung, die früher fällig ist. Ein neues Gerät ohne Fortschritt
übernimmt den Stand des Kontos; hat es eigenen Fortschritt, fragt die App einmal.

## Mails

Bestätigungs- und Passwort-Mails gehen über ein eigenes Gmail-Konto der App (SMTP mit
App-Passwort, in Supabase unter Authentication → Emails → SMTP eingetragen). Die Texte stehen
in der Auth-Einstellung des Projekts, in vier Sprachen: Die App gibt beim Registrieren die
Sprache mit (`lang` in den Nutzerdaten), die Vorlagen wählen danach (`{{ if eq .Data.lang "en" }}`).
Neue Konten müssen ihre E-Mail-Adresse bestätigen. Ein Link aus der Mail öffnet die App:
bestätigt → Konto-Seite mit Begrüßung; Passwort vergessen → Formular für ein neues Passwort;
abgelaufen → Hinweis.

## Noch offen

- Anmeldung mit Google (Google-Cloud-Projekt) und Apple (Apple-Entwicklerkonto).
- Tägliche Erinnerung per Push.
