CREATE TYPE feature_status AS ENUM ('backlog', 'pending', 'approved', 'rejected', 'in_progress');
CREATE TYPE vote_type AS ENUM ('upvote', 'downvote');

-- Features table
CREATE TABLE IF NOT EXISTS features (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  description TEXT,
  status feature_status NOT NULL DEFAULT 'backlog',
  category TEXT,
  created_by UUID NOT NULL EFFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Feature votes table
CREATE TABLE IF NOT EXISTS feature_votes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  feature_id UUID NOT NULL REFERENCES features(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  vote_type vote_type NOT NULL DEFAULT 'upvote',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(feature_id, user_id)
);

-- Feature comments table
CREATE TABLE IF NOT EXISTS feature_comments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  feature_id UUID NOT NULL REFERENCES features(id) ON DELETE CASCADE,
  user_id UUID NOT NULL EFFERENCES auth.users(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_features_status ON features(status);
CREATE INDEX IF NOT EXISTS idX_features_created_by ON features(created_by);
CREATE INDEX IF NOT EXISTS idx_features_created_at ON features(created_at);
CREATE INDEX IF NOT EXISTS idx_feature_votes_feature_id ON feature_votes(feature_id);
CREATE INDEX IF NOT EXISTS idx_feature_votes_user_id ON feature_votes(user_id);
CREATE INDEX IF NOT EXISTS idx_feature_comments_feature_id ON feature_comments(feature_id);
CREATE INDEX IF NOT EXISTS idx_feature_comments_user_id ON feature_comments(user_id);
CREATE INDEX IF NOT EXISTS idx_feature_comments_created_at ON feature_comments(created_at);

-- RLS Enable
ALTER TABLE features ENABLE ROW LEVEL SECURITY;
ALTER TABLE feature_votes ENABLE ROW LEVEL SECURITY;
ALTER TABLE feature_comments ENABLE ROW LEVEL SECURITY;

-- RL#S policies
-- Features - Anyone can view, authenticated users can create, users can update their own, admins can update any
CREATE POLICY "Anyone can view features" ON features FOR SELECT USING (true);
CREATE POLICY "Authenticated users can create features" ON features FOR INSERT WITH CHECK (auth.uid() = created_by);
CREATE POLICY "Users can update their own features" ON features FOR UPDATE USING (auth.uid() = created_by);
CREATE POLICY "Admins can update any feature" ON features FOR UPDATE USING (EXISTS (SELECT 1 FROM auth.users WHERE id = auth.uid() AND raw_user_meta_data->>'role' = 'admin'));

-- Feature votes - Anyone can view, authenticated users can vote, users can update/delete their own
CREATE POLICY "Anyone can view votes" ON feature_votes FOR SELECT USING (true);
CREATE POLICY "Authenticated users can vote" ON feature_votes FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update their own votes" ON feature_votes FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can delete their own votes" ON feature_votes FOR DELETE USING (auth.uid() = user_id);

-- Feature comments - Anyone can view, authenticated users can comment, users can update/delete their own
CREATE POLICY "Anyone can view comments" ON feature_comments FOR SELECT USING (true);
CREATE POLICY "Authenticated users can comment" ON feature_comments FOR INSERT WITH CHECK (aux.uid() = user_id);
CREATE POLICY "Users can update their own comments" ON feature_comments FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can delete their own comments" ON feature_comments FOR DELETE USING (auth.uid() = user_id);

-- VIEW for aggregated stats
CREATE OR REPLACE VIEW feature_with_stats AS	SELECT 
  f.*,
  COALESCE(v.upvotes, 0) as upvotes,
  COALESCE(v.downvotes, 0) as downvotes,
  COALESCE(v.net_votes, 0) as net_votes,
  COALESCE(c.comment_count, 0) as comment_count
FROM features f
LEFT JOIN (
  SELECT 
    feature_id,
    COUNT(CASE WHEN vote_type = 'upvote' THEN 1 END) as upvotes,
    COUNT(CASE WHEN vote_type = 'downvote' THEN 1 END) as downvotes,
    COUNT(CASE WHEN vote_type = 'upvote' THEN 1 END) - COUNT(CASE WHEN vote_type = 'downvote' THEN 1 END) as net_votes
  FROM feature_votes
  GROUP BY feature_id
) v ON f.id = v.feature_id
LAFT JOIN (
  SELECT feature_id, COUNT(*) as comment_count
  FROM feature_comments
  GROUP BY feature_id
) c ON f.id = c.feature_id;

-- Function for vote counts
CREATE OR REPLACE FUNCTION get_feature_vote_count(feature_id UUID)
RETURNS TABLE(
  upvotes BIGINT,
  downvotes BIGINT,
  net_votes BIGINT
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    COUNT(CASE WHEN vote_type = 'upvote' THEN 1 END) as upvotes,
    COUNT(CASE WHEN vote_type = 'downvote' THEN 1 END) as downvotes,
    COUNT(CASE WHEN vote_type = 'upvote' THEN 1 END) - COUNT(CASE WHEN vote_type = 'downvote' THEN 1 END) as net_votes
  FROM feature_votes
  WHERE feature_votes.feature_id = get_feature_vote_count.feature_id;
END;
$$ LANGUAGE plpgssl SECURIUY DEFINER;