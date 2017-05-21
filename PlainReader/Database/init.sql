DROP TABLE IF EXISTS article;
DROP TABLE IF EXISTS top_comment;
DROP TABLE IF EXISTS weekly;
DROP TABLE IF EXISTS starred;

CREATE TABLE article (
	id INTEGER PRIMARY KEY,
	title TEXT,
	category TEXT,
	source TEXT,
	summary TEXT,
	pubtime TEXT,
	content TEXT,
	cmt_count INTEGER,
	sn TEXT,
	csrf_token TEXT,
	comment_csrf TEXT,
	thumb TEXT,
	is_read INTEGER,
	cache_status INTEGER
);

CREATE TABLE top_comment (
	id INTEGER PRIMARY KEY AUTOINCREMENT,
    hash TEXT UNIQUE,
	content TEXT,
	location TEXT,
	article_id INTEGER
);

CREATE TABLE weekly (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
	article_id INTEGER,
	type INTEGER
);

CREATE TABLE starred (
    article_id INTEGER PRIMARY KEY,
    time INTERGER
);
