function saveTweets(twty,S)
%Collect Tweets from Streaming API and save them to data field of Twitty 
% objeect. Define this as output function of Twitty object, i.e. twty.outFcn
%
% INPUT:
%  twty - the instance of the twitty class.
%  S    - cell array of structures containing the tweets to analyse. 
% OUTPUT: none. 
%         Computed statistics are stored in the twitty's designated property: 'twty.data'.
%
% Example: 
%  tw=twitty; tw.sampleSize = 3000; tw.outFcn = @saveTweets; tw.sampleStatuses; tw.data;

% Check the input:
narginchk(2, 2);

% Parse input:
if length(S)==1 && isfield(S{1}, 'statuses')
    T = S{1}.statuses;
else
    T = S;
end

% Initialization:
if ~twty.data.outFcnInitialized
    twty.data.statuses = {}; % structure arrays of tweets in a cell array
    twty.data.tweetscnt = 0;   % general number of tweets.
    twty.data.originalcnt = 0; % number of original tweets (not retweets or mentioning others).
    twty.data.mentionscnt = [0, 0]; % number of mentions: replies and retweets.
    twty.data.hashtagscnt = 0;  % number of tweets containing a hashtag.
    twty.data.urlscnt = 0;      % number of tweet containing an url link.
    
    % Initialization done.
    twty.data.outFcnInitialized = 1; 
end

% Process tweets:
if ~isempty(T), twty.data.statuses = [twty.data.statuses T]; end
for ii=1:length(T)
    if isfield(T{ii},'entities')
        twty.data.tweetscnt = twty.data.tweetscnt+1;
        if ~isempty(T{ii}.entities.hashtags), twty.data.hashtagscnt = twty.data.hashtagscnt+1; end
        if ~isempty(T{ii}.entities.user_mentions)
            if strfind(T{ii}.text,'RT @') 
                twty.data.mentionscnt(2) = twty.data.mentionscnt(2)+1;
            else
                twty.data.mentionscnt(1) = twty.data.mentionscnt(1)+1;
            end
        else
            twty.data.originalcnt = twty.data.originalcnt+1;
        end
        if ~isempty(T{ii}.entities.urls), twty.data.urlscnt = twty.data.urlscnt+1; end
    end
end

% Display a "progress bar":
clc;
disp(['Tweets processed: ' num2str(twty.data.tweetscnt) ' (out of ' num2str(twty.sampleSize) ').']);
end

