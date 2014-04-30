classdef processTweets
    %PROCESSTWEETS provides utility methods to process tweets in structure
    %arrays generated from JSON
    
    methods (Static)
        
        function [users,tweets,varargout] = extract(S)
            if length(S) == 1
                statuses = S{1}.statuses;
            else
                statuses = S;
            end
            
            % iterate over the returned result to extract details
            tweet_ids = zeros(length(statuses),1);
            names = cell(length(statuses),1);
            screen = cell(length(statuses),1);
            user_ids = zeros(length(statuses),1);
            followers = zeros(length(statuses),1);
            tweet_texts = cell(length(statuses),1);
            hashtags = cell(length(statuses),1);
            mentions = cell(length(statuses),1);
            retweeted = zeros(length(statuses),1);
            isRT = false(length(statuses),1);
            isCommercial = false(length(statuses),1);
            isHindi = false(length(statuses),1);
            hindi = {'hai','ki','ka','kya','ke','hain','na','sy','se','daadi','bhi','di','sonay'};
            for i=1:length(statuses)
                tweet_ids(i) = statuses{i}.id;
                names{i} = statuses{i}.user.name;
                screen{i} = statuses{i}.user.screen_name;
                user_ids(i) = statuses{i}.user.id;
                followers(i) = statuses{i}.user.followers_count;
                tweet_texts{i} = regexprep(statuses{i}.text,'\r\n|\n|\r',' ');
                retweeted(i) = statuses{i}.retweeted;
                if ~isempty(strfind(statuses{i}.text,'RT @')) || isfield(statuses{i},'retweeted_status')
                    isRT(i) = true;
                end
                if ~isempty(statuses{i}.entities.hashtags)
                    for j = 1:length(statuses{i}.entities.hashtags)
                        hashtags{i,j} = statuses{i}.entities.hashtags{j}.text;
                    end
                end
                if sum(ismember(lower(hashtags(i,~cellfun('isempty',hashtags(i,:)))),...
                        {'job','jobs','career','recruitment','sales'})) > 0
                    isCommercial(i) = true;
                end
                if ~isempty(statuses{i}.entities.user_mentions)
                    for k = 1:length(statuses{i}.entities.user_mentions)
                        mentions{i,k} = statuses{i}.entities.user_mentions{k}.screen_name;
                    end
                end
                tokens = textscan(tweet_texts{i},'%s','Delimiter',' ');
                tokens = tokens{1}(:);
                if sum(ismember(tokens, hindi)) > 0
                    isHindi(i) = true;
                end
            end
            
            % remove duplicates and get the tweet counts
            [names,tweet_idx,user_idx] = unique(names);
            screen = screen(tweet_idx);
            user_ids = user_ids(tweet_idx);
            followers = followers(tweet_idx);
            freq = accumarray(user_idx,1);
            
            % create a table
            users = table(names,screen,user_ids,freq,followers,tweet_texts(tweet_idx),isCommercial(tweet_idx),isHindi(tweet_idx),...
                'VariableNames',{'Name','Screen_Name','Id','Freq','Followers','Tweet','isCommercial','isHindi'});
            
            % if user name contains 'jobs', mark it as commercial
            users.isCommercial(~cellfun('isempty',strfind(lower(users.Name),'jobs'))) = true;
            
            tweets = table(tweet_ids,user_idx,tweet_texts,isCommercial,isHindi,isRT,retweeted,hashtags,mentions,...
                'VariableNames',{'Id','UserIdx','Tweet','isCommercial','isHindi','isRT','Retweeted','Hashtags','Mentions'});
            varargout = {tweet_idx};
        end
        
        function [tokenized,varargout] = tokenize(tweets,stopwordsURL)
            % load stop words data
            stopWords = urlread(stopwordsURL);
            stopWords = textscan(stopWords,'%s','Delimiter',',');
            stopWords = stopWords{1}(:);
            
            % remove special characters in tokenization
            delimiters = {' ','$','/','.','-',':','&','*',...
                            '+','=','[',']','?','!','(',')','{','}',',',...
                            '"','>','_','<',';','%',char(10),char(13)};
            
            % iterate over tweets
            tokenized = cell(size(tweets.Tweet));
            word_list = {};
            
            for i = 1:length(tweets.Tweet)
                % lower case 
                tweet = lower(tweets.Tweet{i});
                % remove numbers
                tweet = regexprep(tweet, '[0-9]+','');
                % remove URLs
                tweet = regexprep(tweet,'(http|https)://[^\s]*','');
                % check if tweet is still valid
                if ~isempty(tweet)
                        % tokenize the content - returns a nested cell array
                        tokens = textscan(tweet,'%s','Delimiter',delimiters);
                        tokens = tokens{1}(:);
                        % remove unicode characters
                        tokens = regexprep(tokens,'\\u','');
                        % remove empty elements
                        tokens = tokens(~cellfun('isempty',tokens));
                        % remove stopwords 
                        tokens = tokens(~ismember(tokens, stopWords));
                        % remove one character words
                        tokens = tokens(cellfun('length',tokens) > 1);
                        % store tokens
                        tokenized{i,1} = tokens;
                        word_list = [word_list;tokens];
                end
            end
            varargout = {word_list};
        end
        
        function scores = scoreSentiment(tweets,scoreFile,stopwordsURL)
            % load AFINN data
            AFINN = readtable(scoreFile,'Delimiter','\t','ReadVariableNames',0);
            AFINN.Properties.VariableNames = {'Term','Score'};
            % tokenize tweets
            tokenized = processTweets.tokenize(tweets,stopwordsURL);
            
            % compute sentiment scores
            scores = zeros(size(tokenized));
            for i = 1:length(tokenized)
                % if the tweet is commercial or in Hindi, skip it
                if ~(tweets.isCommercial(i) || tweets.isHindi(i))
                    % compute the sentiment score
                    scores(i) = sum(AFINN.Score(ismember(AFINN.Term,tokenized{i})));
                end
            end
        end
        
        function [timelineWords,varargout] = wordsInTimeline(tw,user_ids,stopwordsURL)
            users = [];
            ids = [];
            vocab = {};
            counts = [];
            hashtags = [];
            hashtags_by = [];
            hashtags_count = [];
            mentions = [];
            mentions_by = [];
            mentions_count = [];

            for i = 1:length(user_ids)
                S = tw.userTimeline('user_id',user_ids(i),'count',200);
                [~,tweets] = processTweets.extract(S);
                [~,word_list] = processTweets.tokenize(tweets,stopwordsURL);
                [words,~,idx] = unique(word_list); 
                vocab = [vocab;words];
                counts = [counts; accumarray(idx,1)];
                users = [users;repmat(i,size(words))];
                ids = [ids;repmat(user_ids(i),size(words))];
                entities = tweets.Hashtags;
                entities = entities(~cellfun('isempty',entities));
                [entities,~,idx] = unique(entities);
                hashtags = [hashtags; entities];
                hashtags_count = [hashtags_count; accumarray(idx,1)];
                hashtags_by = [hashtags_by;repmat(i,size(entities))];
                entities = tweets.Mentions;
                entities = entities(~cellfun('isempty',entities));
                [entities,~,idx] = unique(entities);
                mentions = [mentions;entities];
                mentions_count = [mentions_count; accumarray(idx,1)];
                mentions_by = [mentions_by;repmat(i,size(entities))];
            end
            timelineWords = table(users,ids,vocab,counts,'VariableNames',{'User','Id','Word','Count'});
            % if a word contains '@', then it is username or email address.
            timelineWords(~cellfun('isempty',strfind(timelineWords.Word,'@')),:) = [];
            % if a word is 'rt' or 'amp', remove
            timelineWords(ismember(timelineWords.Word,{'rt','amp'}),:) = [];
            % remove special characters like #, ', and \
            timelineWords.Word = cellfun(@(x) regexprep(x, '[#''\\]',''),timelineWords.Word,'UniformOutput',false);
            
            timelineHashtags = table(hashtags_by,hashtags,hashtags_count,'VariableNames',{'User','Hashtag','Count'});
            timelineMentions = table(mentions_by,mentions,mentions_count,'VariableNames',{'User','Mention','Count'});
            
            [vocab,~,idx] = unique(timelineWords.Word);
            totalCounts = accumarray(idx,timelineWords.Count);
            dict = table(vocab,totalCounts,'VariableNames',{'Word','Count'});
            
            varargout = {dict,timelineHashtags,timelineMentions};
        end
        
        function saveEdgeList(S,filename)
            [users,tweets] = processTweets.extract(S);
            from = {};
            to = {};
            for i = 1:height(tweets)
                hashtags = tweets.Hashtags(i);
                if ~cellfun('isempty',hashtags)
                    for j = 1:length(hashtags)
                        from = [from; ['@' users.Screen_Name{tweets.UserIdx(i)}]];
                        to = [to; ['#' hashtags{j}]];
                    end
                end
                mentions = tweets.Mentions(i);
                if ~cellfun('isempty',mentions)
                    for k = 1:length(hashtags)
                        from = [from; ['@' users.Screen_Name{tweets.UserIdx(i)}]];
                        to = [to; ['@' mentions{k}]];
                    end
                end
            end
            writetable(table(from,to),filename,'WriteVariableNames',false)
            fprintf('File "%s" was successfully saved.\n\n',filename)
        end
    end
    
end

