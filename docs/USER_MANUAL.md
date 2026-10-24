# Owleo Nest — User Manual

For academy owners, trainers and students. Owleo Nest runs your performing-arts academy in one app:
courses, batches, timetable, attendance, fees, study material, events and messages — plus a Social
feed for artists.

What you see depends on **your role** and on **which features your academy admin has switched on for
you**. If a tile below is missing, you have not been given that feature — ask your admin.

## 1. Getting started

1. Open the app (web or phone) and choose **Log in**. New artists can **Sign up** or
   **Become an artist**.
2. Forgot your password? Use the reset link; a one-time code is emailed to you.
3. If you belong to more than one academy, switch between them from the header — everything on screen
   then belongs to the academy you picked.
4. **App Lock** (Settings) asks for your device unlock before the app opens.

**Navigation.** The bottom bar has **Dashboard**, **Attendance**, **Fees** and **More**. **More** opens
a grid of everything else you can use.

## 2. Roles at a glance

| Role | Can do |
|---|---|
| **Super Admin** | Onboard academies, see platform metrics and settings. No academy of their own. |
| **Academy Admin** | Everything in their academy, including courses, academy profile, messages, settings, plans and invoices. |
| **Trainer** | Only what the admin granted (see features below), only for the courses they were granted. Always sees study material, students and the academy profile. |
| **Student** | Own courses, attendance, fees, schedule, events, study material, profile. |
| **Artist / Guest** | Social side only. |

Features an admin can give a trainer: Student registration, Trainer registration, Batch creation,
Batch scheduling, Reschedule, Attendance, Fees entry, Fees dashboard, Syllabus/Study Material edit,
Event management, Artist-style posting. Course management and Academy-profile editing stay with
admins.

## 3. Modules

### Dashboard
Your home screen: tiles for everything you can open, plus today's summary. Students see their own
classes and fees.

### Courses *(Admin)* / My Courses *(Student)*
Create a course: name, category, icon, billing day and payment methods. Courses are listed A–Z.
Students see the courses they are enrolled in.

### Batches *(Batch creation)*
A batch is a group of students learning a course together. Set start/end dates, add students and
assign one or more trainers. Pick a course first, then the batch.

### Batch Scheduling *(Batch scheduling / Reschedule)*
The timetable. Add weekly classes to a batch. From the feed you can **reschedule** a class, **cancel**
it with a reason, or assign a **substitute trainer** for one class. Students and trainers are
notified.

### Attendance *(Attendance)*
Pick a course, batch and class, then mark each student present or absent. The home screen shows a
calendar with marks per day and a month picker; filter by course/batch. Students see their own
attendance only.

### Fees *(Fees entry / Fees dashboard)*
- **Landing:** collected vs pending for the month.
- **Student detail:** a student's fees, slips and payments; record a payment or generate a slip.
- **Other fees:** one-off charges (costumes, exams, events) for a batch or one student.
- **Dashboard:** charts of collection over time.
Students see only their own fees.

### Study Material *(everyone views; Syllabus edit to upload)*
Files, songs, documents and images attached to a **batch**. Features: choose which students may see
an item, shared **Song / Document / Image libraries** across batches, **playlists** (drag to reorder,
repeat a song), a file viewer, and a **practice player** with tempo and volume, loop and multi-segment
trims, saved per person per track. Documents open as a cover card with a download button (no in-app
PDF reader yet).

### Users *(Student / Trainer registration)*
Add students and trainers: name, contact, role details, salary (trainers), and the course/batch they
belong to. Grant a trainer features and the courses they apply to.

### Students
Search and open a student profile across the courses you can see.

### Events *(Event management)*
Create an event, pick its audience (whole academy, courses, batches or individuals), schedule it and
set its status. Students see events meant for them.

### Messages *(Admin)*
Send a broadcast to the academy, chosen courses, batches or individuals. Recipients get an in-app
notification.

### Academy Profile
About us, contact details, address, cover image, highlight gallery and featured trainers. Everyone
can read it; those with Academy-profile edit can change it.

### Settings
Admin: your password, the academy's plan and invoices. Student: password, language, App Lock.

### Profile *(Student)*
Your photo, details, **achievements** and **performance logs** your trainers record.

### Social
A feed of posts and events from artists. Create a post with photos, search profiles, browse a
profile's posts. Trainers with *Artist-style posting* post with an artist card.

### Notifications
The bell shows unread items — fee reminders, schedule changes, broadcasts.

## 4. Common tasks

| I want to… | Go to |
|---|---|
| Mark today's attendance | Attendance → course → batch → class → tick students → Save |
| Move a class | More → Batch Scheduling → open the class → Reschedule |
| Cover for an absent trainer | Batch Scheduling → class → Substitute trainer |
| Record a fee payment | Fees → student → Add payment |
| Charge a one-off fee | Fees → Other fees → New |
| Share a song with one batch | More → Study Material → pick batch → Add |
| Let a trainer take attendance | More → Users → trainer → grant *Attendance* for the course |
| Tell everyone about a holiday | More → Messages → New broadcast |

## 5. Troubleshooting

- **"I can't see a tile."** You lack that feature or the right course — ask your admin.
- **"I see nothing in a course picker."** You haven't been granted any course for that feature.
- **First load after a quiet period is slow.** The server sleeps on the free plan; wait about a minute.
- **Everything fails after a new deploy.** Report to the developer: the site's web address may not be
  allowed on the server (CORS).
- **A document won't open in the app.** Use Download; documents have no in-app viewer yet.

*Written from the app's modules and permissions; screen labels may differ slightly from the latest build.*
