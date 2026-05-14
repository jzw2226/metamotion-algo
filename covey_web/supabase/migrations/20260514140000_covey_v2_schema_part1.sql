-- Covey v2 production schema (Part 1 of 3)
-- Identity: profiles, sensitive split, social links, settings, blocks,
-- activity taxonomy, auth signup bootstrap, RLS for identity domain.

-- ---------------------------------------------------------------------------
-- 1. Extensions
-- ---------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ---------------------------------------------------------------------------
-- 3. Enum types
-- ---------------------------------------------------------------------------
CREATE TYPE public.discovery_visibility AS ENUM ('public', 'friends', 'private');
CREATE TYPE public.social_platform AS ENUM (
  'instagram', 'twitter', 'tiktok', 'linkedin', 'youtube', 'website', 'other'
);
CREATE TYPE public.plan_status AS ENUM ('draft', 'published', 'cancelled', 'completed', 'archived');
CREATE TYPE public.plan_visibility AS ENUM ('public', 'friends', 'invite_only', 'unlisted');
CREATE TYPE public.hangout_type AS ENUM ('casual', 'event', 'date', 'professional');
CREATE TYPE public.join_mode AS ENUM ('open', 'request', 'invite');
CREATE TYPE public.plan_attendee_role AS ENUM ('host', 'cohost', 'attendee');
CREATE TYPE public.plan_attendee_status AS ENUM ('going', 'maybe', 'left', 'removed');
CREATE TYPE public.join_request_status AS ENUM ('pending', 'approved', 'declined', 'cancelled');
CREATE TYPE public.plan_invite_status AS ENUM ('pending', 'accepted', 'declined', 'cancelled');
CREATE TYPE public.transport_type AS ENUM ('walk', 'bike', 'car', 'rideshare', 'transit', 'other');
CREATE TYPE public.chat_message_type AS ENUM ('text', 'system');
CREATE TYPE public.arrival_status AS ENUM ('on_the_way', 'running_late', 'arrived', 'cancelled');
CREATE TYPE public.friendship_status AS ENUM ('pending', 'accepted', 'declined', 'blocked');
CREATE TYPE public.notification_type AS ENUM (
  'friend_request',
  'friend_accept',
  'plan_invite',
  'join_request',
  'join_approved',
  'join_declined',
  'plan_update',
  'chat_message',
  'arrival_update'
);
CREATE TYPE public.plan_interaction_type AS ENUM (
  'impression', 'view', 'save', 'join_click', 'request', 'chat', 'attend'
);

-- ---------------------------------------------------------------------------
-- 4. updated_at trigger helper
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- 5. Profiles + privacy-sensitive split
-- ---------------------------------------------------------------------------
CREATE TABLE public.profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  username text NOT NULL UNIQUE,
  display_name text NOT NULL,
  full_name text,
  avatar_url text,
  bio text,
  home_city text,
  onboarding_completed boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT profiles_username_lower CHECK (username = lower(username)),
  CONSTRAINT profiles_username_format CHECK (username ~ '^[a-z0-9_]{3,30}$')
);

CREATE TABLE public.profile_sensitive (
  user_id uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  birthdate date,
  gender text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT profile_sensitive_gender_chk CHECK (
    gender IS NULL OR gender IN ('female', 'male', 'nonbinary', 'prefer_not_to_say', 'other')
  )
);

CREATE TABLE public.profile_social_links (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  platform public.social_platform NOT NULL,
  url text NOT NULL,
  handle text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, platform)
);

CREATE TABLE public.user_settings (
  user_id uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  push_notifications_enabled boolean NOT NULL DEFAULT true,
  email_notifications_enabled boolean NOT NULL DEFAULT true,
  discovery_visibility public.discovery_visibility NOT NULL DEFAULT 'public',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.user_blocks (
  blocker_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  blocked_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (blocker_id, blocked_id),
  CONSTRAINT user_blocks_not_self CHECK (blocker_id <> blocked_id)
);

-- ---------------------------------------------------------------------------
-- 6. Activity taxonomy
-- ---------------------------------------------------------------------------
CREATE TABLE public.activity_categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug text NOT NULL UNIQUE,
  label text NOT NULL,
  sort_order int NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.activities (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug text NOT NULL UNIQUE,
  label text NOT NULL,
  category_id uuid NOT NULL REFERENCES public.activity_categories(id) ON DELETE RESTRICT,
  embedding_text text,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.user_activity_preferences (
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  activity_id uuid NOT NULL REFERENCES public.activities(id) ON DELETE CASCADE,
  preference_strength int NOT NULL DEFAULT 1,
  proof_photo_url text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, activity_id),
  CONSTRAINT user_activity_preferences_strength_chk CHECK (preference_strength BETWEEN 1 AND 5)
);

CREATE INDEX idx_activities_category ON public.activities(category_id);
CREATE INDEX idx_user_activity_preferences_user ON public.user_activity_preferences(user_id);

-- Triggers: updated_at
CREATE TRIGGER trg_profiles_updated_at
BEFORE UPDATE ON public.profiles
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_profile_sensitive_updated_at
BEFORE UPDATE ON public.profile_sensitive
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_user_settings_updated_at
BEFORE UPDATE ON public.user_settings
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_activities_updated_at
BEFORE UPDATE ON public.activities
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_user_activity_preferences_updated_at
BEFORE UPDATE ON public.user_activity_preferences
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 7. Auth bootstrap: profile + settings + sensitive stub
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  base_handle text;
  chosen_username text;
BEGIN
  base_handle := lower(regexp_replace(split_part(new.email, '@', 1), '[^a-z0-9_]', '', 'g'));
  IF base_handle IS NULL OR length(base_handle) < 3 THEN
    base_handle := 'covey';
  END IF;
  chosen_username := left(base_handle, 30);

  -- collision-safe username
  WHILE exists (select 1 from public.profiles where username = chosen_username) LOOP
    chosen_username := left(base_handle, 20) || substr(replace(gen_random_uuid()::text, '-', ''), 1, 8);
  END LOOP;

  INSERT INTO public.profiles (id, username, display_name)
  VALUES (
    new.id,
    chosen_username,
    coalesce(new.raw_user_meta_data->>'display_name', initcap(replace(chosen_username, '_', ' ')))
  );

  INSERT INTO public.profile_sensitive (user_id) VALUES (new.id);
  INSERT INTO public.user_settings (user_id) VALUES (new.id);

  RETURN new;
END;
$$;

CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

REVOKE ALL ON FUNCTION public.handle_new_user() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.handle_new_user() FROM anon, authenticated;

-- ---------------------------------------------------------------------------
-- 8. RLS: identity domain
-- ---------------------------------------------------------------------------
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profile_sensitive ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profile_social_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_blocks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.activity_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.activities ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_activity_preferences ENABLE ROW LEVEL SECURITY;

CREATE POLICY profiles_select_public_card
ON public.profiles FOR SELECT
TO authenticated
USING (
  id = auth.uid()
  OR EXISTS (
    SELECT 1 FROM public.user_settings s
    WHERE s.user_id = profiles.id
      AND s.discovery_visibility = 'public'
  )
);

CREATE POLICY profiles_insert_own
ON public.profiles FOR INSERT
TO authenticated
WITH CHECK (id = auth.uid());

CREATE POLICY profiles_update_own
ON public.profiles FOR UPDATE
TO authenticated
USING (id = auth.uid())
WITH CHECK (id = auth.uid());

CREATE POLICY profile_sensitive_select_own
ON public.profile_sensitive FOR SELECT
TO authenticated
USING (user_id = auth.uid());

CREATE POLICY profile_sensitive_insert_own
ON public.profile_sensitive FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());

CREATE POLICY profile_sensitive_update_own
ON public.profile_sensitive FOR UPDATE
TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

CREATE POLICY profile_social_links_select_visible
ON public.profile_social_links FOR SELECT
TO authenticated
USING (
  user_id = auth.uid()
  OR EXISTS (
    SELECT 1
    FROM public.user_settings s
    WHERE s.user_id = profile_social_links.user_id
      AND s.discovery_visibility = 'public'
  )
);

CREATE POLICY profile_social_links_manage_own
ON public.profile_social_links FOR ALL
TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

CREATE POLICY user_settings_select_own
ON public.user_settings FOR SELECT
TO authenticated
USING (user_id = auth.uid());

CREATE POLICY user_settings_insert_own
ON public.user_settings FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());

CREATE POLICY user_settings_update_own
ON public.user_settings FOR UPDATE
TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

CREATE POLICY user_blocks_select_involved
ON public.user_blocks FOR SELECT
TO authenticated
USING (blocker_id = auth.uid() OR blocked_id = auth.uid());

CREATE POLICY user_blocks_insert_self
ON public.user_blocks FOR INSERT
TO authenticated
WITH CHECK (blocker_id = auth.uid());

CREATE POLICY user_blocks_delete_self
ON public.user_blocks FOR DELETE
TO authenticated
USING (blocker_id = auth.uid());

CREATE POLICY activity_categories_read_all
ON public.activity_categories FOR SELECT
TO authenticated
USING (true);

CREATE POLICY activities_read_all
ON public.activities FOR SELECT
TO authenticated
USING (is_active = true);

CREATE POLICY user_activity_preferences_select_visible
ON public.user_activity_preferences FOR SELECT
TO authenticated
USING (
  user_id = auth.uid()
  OR EXISTS (
    SELECT 1 FROM public.user_settings s
    WHERE s.user_id = user_activity_preferences.user_id
      AND s.discovery_visibility = 'public'
  )
);

CREATE POLICY user_activity_preferences_manage_own
ON public.user_activity_preferences FOR ALL
TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());
