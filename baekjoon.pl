#!/usr/bin/env perl
package Baekjoon::Evaluator;
use 5.008;
use strict;
use warnings;
use utf8;

use IPC::Open2;

# static sub eval(Baekjoon::Problem)
# 테스트 케이스를 평가합니다.
sub eval {
    my $problem = shift;
    my $program = shift;
    my @input   = @{$problem->test_input};
    my @output  = @{$problem->test_output};
    
    my $is_success = 1;

    printf "%s - 테스트 시작합니다.\n\n", $problem->title;

    for (my $i = 0; $i <= $#input; $i++) {
        warn sprintf "test case #%d ----\ninput:\n%s\n\noutput must be:\n%s\n\n", $i + 1, $input[$i], $output[$i];

        # TODO: 일관적이지 않은 변수명 수정 (output / out가 충돌하잖아!)
        my ($stdin, $stdout, $out);
        my $pid = open2($stdout, $stdin, $program);

        # 테스트 케이스의 입력을 흘려넣고..
        print $stdin $input[$i];
        close $stdin;

        # 출력을 받아서..
        $out .= $_ while <$stdout>;
        close $stdout;
        chomp $out;

        printf "your output:\n%s\n\n", $out;
        # 비교하쟛! 
        printf "test case #%d/%d ... ", $i + 1, $#input + 1;
        printf "%s\n", ($output[$i] eq $out) ? "ok" : "fail";
    }
}

package Baekjoon::Problem;
use 5.008;
use strict;
use warnings;
use utf8;

sub new {
    my $class = shift;
    my $body  = {
        test_input  => [],
        test_output => [],

        $_[0] ? %{ $_[0] } : ()
    };
    return bless $body, $class;
}

sub _attr {
    my ($self, $val, $nv) = @_;
    $self->{$val} = $nv if $nv;
    return $self->{$val};
}

# set_sampledata (div.sampledata.*)
# 샘플 데이터를 설정합니다.
sub set_sampledata {
    my $self     = shift;
    my @elements = @_;

    for my $element (@elements) {
        if ($element->attr("id") =~ m{^sample-(?<type>(input|output))-(?<num>\d+)$}) {
            my $type = sprintf "test_%s", $+{type};
            my $num  = $+{num} - 1;
            my $data = $element->as_text;
            $data =~ s/\s+$//g; # 끝에 붙는 공백 제거

            $self->{$type}->[$num] = $data;
        }
    }
}

for my $attr (qw/title description input output test_input test_output/) {
    eval sprintf 'sub %s { shift->_attr("%s", @_) }', $attr, $attr;
}

package Baekjoon::API;
use 5.008;
use strict;
use warnings;
use utf8;

use LWP::UserAgent;
use HTTP::Cookies;

our $VERSION = "0.1";

sub URL_BASE    () { "https://www.acmicpc.net" }
sub URL_PROBLEM () { URL_BASE."/problem/" }

sub API_BASE    () { URL_BASE."/cmd" }
sub API_SUBMIT  () { API_BASE."/submit" }
sub API_STATUS  () { API_BASE."/status" }

sub UA_DEFAULT_AGENT () { sprintf "Mozilla/5.0 (%s; baekjoon.pl/%s)", $^O, $VERSION }

sub SEARCH_CRITERIA () { {
    title       => { _tag => "span", id => "problem_title" },
    description => { _tag => "div",  id => "problem_description" },
    input       => { _tag => "div",  id => "problem_input" },
    output      => { _tag => "div",  id => "problem_output" },

    set_sampledata  => { _tag => "div", class=> "sampledata" },
} }

sub ERROR_HTML_TREE_NOT_INSTALLED () { "경고: HTML::TreeBuilder 모듈이 설치되어 있지 않습니다. README를 읽어 주십시오." }
sub ERROR_NOT_IMPLEMENTED         () { "해당 기능은 아직 구현되지 않았습니다." }
sub ERROR_PARSE_FAILED            () { "HTML 문서 파싱에 실패하였습니다. 올바른 문제 번호가 아닌 것 같은데요?" }

# sub new([$options])
# 새 인스턴스를 생성합니다.
# s/class/soul/g 하면 뭔가 인체 연성 같이 보인다!!
sub new {

    my ($class, $options) = @_;
    my $body = { 
        _ua => LWP::UserAgent->new(
            agent      => UA_DEFAULT_AGENT,
            cookie_jar => HTTP::Cookies->new, # 쿠키 비활성화 시 CloudFlare에서 잡아가요 엉엉
        ),

        $options ? %{ $options } : (),
    };

    my $self = bless $body, $class;
    return $self;
}

# sub problem($problem_no) => Baekjoon::Problem;
# 문제 정보를 가지고 옵니다.
sub problem {
    my $self       = shift;
    my $problem_no = shift;
    
    my $res = $self->_try_request(HTTP::Request->new(GET => URL_PROBLEM . $problem_no), 1);
    
    return $self->_parse_problem($res->decoded_content);
}


sub _parse_problem {
    my $self = shift;

    eval {
        require HTML::TreeBuilder;
    };
    if ($@) {
        die ERROR_HTML_TREE_NOT_INSTALLED;
        # return $self->_parse_problem_regex(@_);
    }

    return $self->_parse_problem_treebuilder(@_);
}

sub _parse_problem_treebuilder {
    my $self    = shift;
    my $content = shift;
    my $problem = Baekjoon::Problem->new;
    my $root    = HTML::TreeBuilder->new_from_content($content);

    my %criteria = %{ SEARCH_CRITERIA() };
    while (my ($attr, $value) = each %criteria) {
        my @elements = $root->look_down(%{ $value });

        die ERROR_PARSE_FAILED unless @elements;

        $problem->$attr(
            $#elements ? @elements : (shift @elements)->as_text
        );
    }

    return $problem;
}

# sub _parse_problem_regex($content)
# HTML 문서를 정규식으로 파싱을 시도합니다.
# 구현되지 않았습니다.
sub _parse_problem_regex {
    my $self    = shift;
    my $content = shift;
    die ERROR_NOT_IMPLEMENTED;
}

# sub _try_request($request)
# HTTP 요청을 시도합니다.
sub _try_request {
    my $self = shift;
    my $req  = shift;

    my $die_on_failed = shift;
    
    my $res  = $self->{_ua}->request($req);
    unless ($res->is_success) {
        warn sprintf "HTTP 요청 실패: %d %s => %s %s", 
             $res->code, $res->message, $req->method, $req->uri;
        die if $die_on_failed;
    }

    return $res;
}

package main;
use 5.008;

use strict;
use warnings;
use utf8;

sub DEFAULT_ENC   () { ($^O eq "MSWin32") ? "euc-kr" : "utf8" }

sub ERROR_NOT_IMPLEMENTED    () { "해당 기능은 아직 구현되지 않았습니다." }
sub ERROR_FILE_NOT_INSTALLED () { "file 명령어가 설치되어 있지 않습니다." }
sub USAGE () {
    return <<EOF;
baekjoon.pl - Baekjoon Online Judge 도우미 스크립트
사용법: baekjoon.pl command [problem] [program] [extra-options]

command: 
    help        이 도움말을 표시합니다.
    --help

    info        문제 정보를 확인합니다.
    get-info    문제 정보를 현재 디렉토리에 저장합니다.
    test        샘플 데이터로 프로그램을 테스트합니다.
    get-test    샘플 데이터를 현재 디렉토리에 저장합니다. (PROBLEM.in / PROBLEM.out)
    submit      프로그램을 제출합니다.

extra-options:
    --force-use-http        HTTPS가 아닌 일반 HTTP로 통신을 강제합니다.
    --force-language LANG   program을 LANG 언어로 취급을 강제합니다.

    --username username     지정된 username과 password로 로그인합니다.   
    --password password     --password 옵션이 입력되지 않으면 echo 없이 입력 받습니다.

그리고:
    - [language]가 지정되지 않으면 file 명령을 통한 자동 검출을 시도합니다.
    - C처럼 빌드 작업이 이루어지는 언어는 테스트 시 [program]에 소스 코드
      대신 컴파일된 바이너리 파일을 입력해 주세요.

    - 계정명은 환경 변수에 BAEKJOON_USERNAME으로 저장하면 쉽게 로그인
      할 수 있습니다. 저장을 원치 않는 경우 --username 옵션을 사용하여
      따로 로그인 해 주세요.

      치즈군★ (unstabler) / doping.cheese\@gmail.com
EOF
}

BEGIN {
    my $enc = sprintf ":encoding(%s)", DEFAULT_ENC;
    binmode STDOUT, $enc;
    binmode STDERR, $enc;
}

sub parse_argv {
    my ($command, $problem, $program, @options) = @_;
    
    my $baekjoon = Baekjoon::API->new;

    if (!$command || $command =~ m{^(--)?help$}) {
        die USAGE; 
    } elsif ($command eq "info" || $command eq "get-info") {
        die ERROR_NOT_IMPLEMENTED; 
    } elsif ($command eq "test" || $command eq "get-test") {
        my $problem = $baekjoon->problem($problem);
        Baekjoon::Evaluator::eval($problem, $program);
    } elsif ($command eq "submit") {

    } else {
        die sprintf "명령 %s는 지원되지 않는 명령입니다.", $command;
    }
}

sub determine_type {
    my $program = shift;

    unless (`which file`) {
        warn ERROR_FILE_NOT_INSTALLED;
        return 0;
    }    
}

parse_argv(@ARGV);
