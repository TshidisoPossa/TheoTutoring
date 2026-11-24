# TheoTutoring


A cross-platform mobile app that connects university students in South Africa with academic tutors. Students can find, book and pay for tutoring sessions, and administrators run the platform behind the scenes.

![Flutter](https://img.shields.io/badge/Flutter-02569B?logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-0175C2?logo=dart&logoColor=white)
![Dart Frog](https://img.shields.io/badge/Dart_Frog-REST_API-0175C2)
![MySQL](https://img.shields.io/badge/MySQL-4479A1?logo=mysql&logoColor=white)
![Firebase](https://img.shields.io/badge/Firebase-FFCA28?logo=firebase&logoColor=black)

> Group project for the BSc in Software Engineering (ITMDA), Eduvos Midrand.

---

## The Problem

University students across South Africa often struggle to access academic tutoring. Scheduling conflicts, limited visibility of tutor availability and the lack of a centralised platform stop many students from getting the help they need. TheoTutoring is an existing South African tutoring platform ([theotutoring.com](https://theotutoring.com)), but it has no dedicated mobile application.

## The Solution

This project designs and builds that mobile application. It centralises tutoring in one place:

- **Students** search for tutors by subject, check availability, book a session, pay, chat with the tutor, and leave a review after the session.
- **Tutors** register through a three-step application, manage their profile, subjects and availability, and accept or decline booking requests.
- **Administrators** approve tutors, manage subjects and users, set the fixed session rate, handle refunds and disputes, pay tutors, and monitor the platform.

## Key Features

- **Role-based app:** separate student, tutor and admin experiences, with access restricted by role
- **Three-step tutor registration** with administrator approval. Tutors are hidden from search until approved
- **Tutor search** with subject filtering, ratings, reviews and availability
- **Booking flow** with clear statuses: Pending → Accepted → Confirmed → Completed (or Declined / Cancelled)
- **Double-booking prevention** and a 3-hour minimum booking notice
- **Payments** by card, PayPal or EFT at a fixed session rate set by the admin
- **Automatic refund calculation** based on cancellation time, with administrator override
- **Real-time chat** between students and tutors
- **Push and email notifications** for bookings, payments, messages and session reminders
- **Reviews and reports:** only students who completed a session can review, and students and tutors can report each other
- **Admin dashboard:** tutor applications, financial overview, refunds and issues, student roster, subject directory, analytics and platform monitoring

---

## Tech Stack

| Layer | Technology |
| --- | --- |
| Frontend (mobile app and admin portal) | Flutter (Dart) |
| Backend | Dart Frog (REST API) |
| Database | MySQL |
| Authentication | Firebase Authentication |
| Chat and in-app notifications | Firebase Firestore |
| Push notifications | Firebase Cloud Messaging |
| File storage | Cloudinary |
| Email | Brevo |
| Payments | Demo (mock) payment gateway |

## Architecture

- The Flutter app talks to the **Dart Frog backend over REST (HTTPS, JSON)**. It never connects to MySQL.
- The backend is the **only component that talks to MySQL**, and holds all the business logic.
- **MySQL** stores structured data (users, bookings, payments, refunds, payouts). **Firestore** stores data that must update in real time (chat and in-app notifications).
- The two databases are linked by IDs, so data is never duplicated.

### Security and validation

- Every protected request carries a **Firebase ID token**, which the backend verifies. Missing or invalid tokens are rejected with `401`.
- The user's identity comes from the verified token, never from the request body.
- The backend checks the user's **role and account status** before allowing an action.
- **All input is validated on the backend**, whatever the app already checked.
- **Parameterised SQL queries** only, and **database transactions** for changes that affect several tables.
- The backend never receives or stores passwords. Firebase Authentication manages credentials.

---

## What This Project Demonstrates

- Full-stack development with **Flutter and Dart** on both the frontend and the backend
- **REST API design** with proper response codes (`200`, `201`, `400`, `401`, `403`, `405`, `409`, `500`)
- **Relational database design** in MySQL, with a schema covering users, bookings, payments, refunds, payouts, reviews and reports
- **Authentication and role-based authorisation** with Firebase
- Integration of **third-party services**: Firebase (Auth, Firestore, FCM), Cloudinary, Brevo and a payment gateway
- Implementing **business rules** in code: booking statuses, availability and overlap checks, refund calculation and tutor approval
- **Design to build:** requirements, use cases, wireframes in Figma, architecture and data design, then implementation
- **Teamwork** with Git and GitHub, using separate branches for frontend, backend, database and integration testing

---

## Team

Group 7, BSc in Software Engineering, Eduvos Midrand. Lecturer: Mr S. Mbatha.

| Name | GitHub | LinkedIn |
| --- | --- | --- |
| Kgalalelo Mashabane | [@username](https://github.com/username) |  
| Nondumiso Fihla | [@username](https://github.com/username) 
| Isabelle Kabongo | [@username](https://github.com/username) 
| Tshidiso Possa | [@username](https://github.com/username) 

## Documentation

Full project documentation (requirements, use cases, screens, architecture, data design and API) is in the project documentation PDF in this repository.
