import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../presentation/landing_screen.dart';
import '../presentation/setup_screen.dart';
import '../presentation/dashboard_screen.dart';
import '../presentation/medications_screen.dart';
import '../presentation/join_team_screen.dart';
import '../presentation/observations_screen.dart';
import '../presentation/observation_history_screen.dart';
import '../presentation/calendar_screen.dart';
import '../presentation/symptom_events_screen.dart';
import '../presentation/symptoms_history_screen.dart';
import '../presentation/moments_screen.dart';
import '../presentation/moments_history_screen.dart';
import '../presentation/care_plan_screen.dart';
import '../presentation/messages.dart';
import '../presentation/what_we_provide_screen.dart';
import '../presentation/how_it_works_screen.dart';
import '../presentation/nurse_patient_list.dart';
import '../presentation/skin_wound_events_screen.dart';
import '../presentation/skin_wounds_screen.dart';
import '../presentation/skin_wounds_history_screen.dart';
import '../presentation/login_screen.dart';
import '../presentation/care_team_screen.dart';
import '../presentation/forgot_password_screen.dart';
import '../presentation/reset_password_screen.dart';
import '../presentation/set_password_after_join_screen.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

final GoRouter appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: '/',
  routes: <RouteBase>[
    GoRoute(
      path: '/',
      builder: (BuildContext context, GoRouterState state) =>
          const LandingScreen(),
    ),
    GoRoute(
      path: '/setup',
      builder: (BuildContext context, GoRouterState state) =>
          const SetupInfoScreen(),
    ),
    GoRoute(
      path: '/join',
      builder: (BuildContext context, GoRouterState state) =>
          const JoinTeamScreen(),
    ),
    GoRoute(
      path: '/set-password',
      builder: (BuildContext context, GoRouterState state) {
        final email = (state.uri.queryParameters['email'] ?? '').trim();
        final code = (state.uri.queryParameters['code'] ?? '').trim();
        final role = (state.uri.queryParameters['role'] ?? '').trim();
        if (email.isEmpty) {
          return LoginScreen(initialError: 'Missing email for password setup');
        }
        return SetPasswordAfterJoinScreen(
          email: email,
          inviteCode: code.isEmpty ? null : code,
          role: role.isEmpty ? null : role,
        );
      },
    ),
    GoRoute(
      path: '/login',
      builder: (BuildContext context, GoRouterState state) => LoginScreen(
        initialEmail: state.uri.queryParameters['email'],
        initialMessage: state.uri.queryParameters['message'],
        initialError: state.uri.queryParameters['error'],
      ),
    ),
    GoRoute(
      path: '/forgot-password',
      builder: (BuildContext context, GoRouterState state) =>
          ForgotPasswordScreen(
            initialEmail: state.uri.queryParameters['email'],
          ),
    ),
    GoRoute(
      path: '/reset-password',
      builder: (BuildContext context, GoRouterState state) =>
          ResetPasswordScreen(errorMessage: state.uri.queryParameters['error']),
    ),
    GoRoute(
      path: '/forgot_password',
      redirect: (BuildContext context, GoRouterState state) {
        final params = state.uri.queryParameters;
        return Uri(
          path: '/forgot-password',
          queryParameters: params.isEmpty ? null : params,
        ).toString();
      },
    ),
    GoRoute(
      path: '/nurse_patients',
      builder: (BuildContext context, GoRouterState state) =>
          const NursePatientList(),
    ),
    GoRoute(
      path: '/dashboard',
      builder: (BuildContext context, GoRouterState state) =>
          const DashboardScreen(),
    ),
    GoRoute(
      path: '/medications',
      builder: (BuildContext context, GoRouterState state) =>
          const MedicationsScreen(),
    ),
    GoRoute(
      path: '/observations',
      builder: (BuildContext context, GoRouterState state) =>
          const ObservationsScreen(),
    ),
    GoRoute(
      path: '/quick-notes-history',
      builder: (BuildContext context, GoRouterState state) =>
          const QuickNotesHistoryScreen(),
    ),
    GoRoute(
      path: '/calendar',
      builder: (BuildContext context, GoRouterState state) =>
          const CalendarScreen(),
    ),
    GoRoute(
      path: '/symptoms',
      builder: (BuildContext context, GoRouterState state) =>
          const SymptomEventsScreen(),
    ),
    GoRoute(
      path: '/symptom-history',
      builder: (BuildContext context, GoRouterState state) =>
          const SymptomHistoryScreen(),
    ),
    GoRoute(
      path: '/skin-wounds',
      builder: (BuildContext context, GoRouterState state) =>
          const SkinWoundEventsScreen(),
    ),
    GoRoute(
      path: '/skin-wounds/new',
      builder: (BuildContext context, GoRouterState state) =>
          const SkinWoundsScreen(),
    ),
    GoRoute(
      path: '/skin-wounds/history',
      builder: (BuildContext context, GoRouterState state) =>
          const SkinWoundsHistoryScreen(),
    ),
    GoRoute(
      path: '/moments',
      builder: (BuildContext context, GoRouterState state) =>
          const MomentsScreen(),
    ),
    GoRoute(
      path: '/moments-history',
      builder: (BuildContext context, GoRouterState state) =>
          const MomentsHistoryScreen(),
    ),
    GoRoute(
      path: '/messages',
      builder: (BuildContext context, GoRouterState state) =>
          const MessagesScreen(),
    ),
    GoRoute(
      path: '/care_plan',
      builder: (BuildContext context, GoRouterState state) =>
          const CarePlanScreen(),
    ),
    GoRoute(
      path: '/care_team',
      builder: (BuildContext context, GoRouterState state) =>
          const CareTeamScreen(),
    ),
    GoRoute(
      path: '/what_we_provide',
      builder: (BuildContext context, GoRouterState state) =>
          const WhatWeProvideScreen(),
    ),
    GoRoute(
      path: '/how_it_works',
      builder: (BuildContext context, GoRouterState state) =>
          const HowItWorksScreen(),
    ),
  ],
);
