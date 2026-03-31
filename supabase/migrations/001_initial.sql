-- ============================================
-- 디지털무역 전략카드 웹앱 - DB 스키마 (최종)
-- Supabase SQL Editor에서 실행하세요
-- ============================================

-- 기존 테이블 삭제 (깨끗하게 시작)
DROP TABLE IF EXISTS ai_recommendations CASCADE;
DROP TABLE IF EXISTS card_responses CASCADE;
DROP TABLE IF EXISTS card_progress CASCADE;
DROP TABLE IF EXISTS profiles CASCADE;
DROP TABLE IF EXISTS teams CASCADE;

-- 1. 팀 테이블
CREATE TABLE teams (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  join_code TEXT UNIQUE NOT NULL DEFAULT substr(md5(random()::text), 1, 6),
  product_name TEXT,
  product_description TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. 프로필 테이블
CREATE TABLE profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT,
  name TEXT NOT NULL,
  school TEXT DEFAULT '동구고등학교',
  team_id UUID REFERENCES teams(id) ON DELETE SET NULL,
  role TEXT DEFAULT 'student' CHECK (role IN ('student', 'teacher', 'admin')),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. 카드 진행 상태
CREATE TABLE card_progress (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id UUID NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
  card_id TEXT NOT NULL,
  checklist_status JSONB DEFAULT '{}',
  completed BOOLEAN DEFAULT FALSE,
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(team_id, card_id)
);

-- 4. 카드 응답
CREATE TABLE card_responses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id UUID NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
  card_id TEXT NOT NULL,
  texts JSONB DEFAULT '{}',
  images JSONB DEFAULT '{}',
  created_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(team_id, card_id)
);

-- 5. AI 추천 결과
CREATE TABLE ai_recommendations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id UUID NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
  input_summary JSONB,
  recommendation TEXT,
  strategy_type TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- RLS 비활성화 (교육용 - 간단하게)
-- ============================================
ALTER TABLE teams DISABLE ROW LEVEL SECURITY;
ALTER TABLE profiles DISABLE ROW LEVEL SECURITY;
ALTER TABLE card_progress DISABLE ROW LEVEL SECURITY;
ALTER TABLE card_responses DISABLE ROW LEVEL SECURITY;
ALTER TABLE ai_recommendations DISABLE ROW LEVEL SECURITY;

-- ============================================
-- 트리거: updated_at 자동 갱신
-- ============================================
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS card_progress_updated ON card_progress;
CREATE TRIGGER card_progress_updated
  BEFORE UPDATE ON card_progress
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

DROP TRIGGER IF EXISTS card_responses_updated ON card_responses;
CREATE TRIGGER card_responses_updated
  BEFORE UPDATE ON card_responses
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ============================================
-- 새 유저 가입 시 프로필 자동 생성
-- ============================================
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, email, name)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'name', split_part(NEW.email, '@', 1))
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- ============================================
-- 기존 유저 프로필 생성 (이미 가입된 유저용)
-- ============================================
INSERT INTO profiles (id, email, name, school)
SELECT id, email, COALESCE(raw_user_meta_data->>'name', split_part(email, '@', 1)), '동구고등학교'
FROM auth.users
ON CONFLICT (id) DO NOTHING;
