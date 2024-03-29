#lang eopl

; Environments.
(define identifier? symbol?)

(define-datatype env env?
  (empty-env)
  (extend-env (k identifier?) (v expval?) (e env?))
  (extend-env-rec (f identifier?) (x identifier?)
                  (body expression?) (e env?))
  (extend-env-rec* (bindings list?) (e env?)))

(define (empty-env? e)
  (cases env e
    (empty-env () #t)
    (else #f)))

(define (report-no-binding-found k)
  (eopl:error 'apply-env "No binding for ~s" k))

(define (apply-list k bindings e e1)
  (cond
    [(null? bindings) (apply-env k e1)]
    [else
     (cases letrec*-binding (car bindings)
       (binding-exp (f x body)
                    (if (eqv? f k)
                        (proc-val (procedure x body e))
                        (apply-list k (cdr bindings) e e1))))]))

(define (apply-env k e)
  (cases env e
    (empty-env () (report-no-binding-found k))
    (extend-env (k2 v e1) (if (eqv? k k2) v (apply-env k e1)))
    (extend-env-rec (f x body e1)
                    (if (eqv? f k)
                        (proc-val (procedure x body e))
                        (apply-env k e1)))
    (extend-env-rec* (bindings e1) (apply-list k bindings e e1))))

; Lexical specification and grammar.
(define the-lexical-spec
  '((whitespace (whitespace) skip)
    (comment ("%" (arbno (not #\newline))) skip)
    (identifier
     (letter (arbno (or letter digit "_" "-" "?")))
     symbol)
    (number (digit (arbno digit)) number)
    (number ("-" digit (arbno digit)) number)))

(define the-grammar
  '((program (expression) a-program)
    
    (expression (number) const-exp)
    (expression
     ("-" "(" expression "," expression ")")
     diff-exp)
    
    (expression
     ("zero?" "(" expression ")")
     zero?-exp)
    
    (expression
     ("if" expression "then" expression "else" expression)
     if-exp)
    
    (expression (identifier) var-exp)
    
    (expression
     ("let" identifier "=" expression "in" expression)
     let-exp)

    (expression
     ("proc" "(" identifier ")" expression)
     proc-exp)

    (expression
     ("(" expression expression ")")
     call-exp)

    (expression
     ("letrec" identifier "(" identifier ")"
               "=" expression "in" expression)
     letrec-exp)
    
    (letrec*-binding
     (identifier "(" identifier ")" "=" expression)
     binding-exp)

    (expression
     ("letrec*" (arbno letrec*-binding) "in" expression)
     letrec*-exp)))

; SLLGEN boilerplate.

(sllgen:make-define-datatypes the-lexical-spec the-grammar)

(define show-the-datatypes
  (lambda () (sllgen:list-define-datatypes the-lexical-spec the-grammar)))

(define scan&parse
  (sllgen:make-string-parser the-lexical-spec the-grammar))

(define just-scan
  (sllgen:make-string-scanner the-lexical-spec the-grammar))

; Expressed (expressible?) values for the PROC language.
(define (procedure var body env)
  (lambda (val) (value-of body (extend-env var val env))))

(define (apply-procedure f x) (f x))

(define-datatype expval expval?
  (num-val
   (num number?))
  (bool-val
   (bool boolean?))
  (proc-val
   (proc procedure?)))

(define (expval->num val)
  (cases expval val
    (num-val (num) num)
    (else 'WUT)))

(define (expval->bool val)
  (cases expval val
    (bool-val (bool) bool)
    (else 'WUT2)))

(define (expval->proc val)
  (cases expval val
    (proc-val (p) p)
    (else 'WUT3)))

(define (expval->any val)
  (cases expval val
    (num-val (n) n)
    (bool-val (b) b)
    (proc-val (p) p)))

; The initial environment.
; init-env : () -> Env
(define (init-env)
  (extend-env
   'i (num-val 1)
   (extend-env
    'v (num-val 5)
    (extend-env
     'x (num-val 10)
     (empty-env)))))

; Interpreter for the LET language.
; run : String -> ExpVal
(define (run string)
  (value-of-program (scan&parse string)))

(define (run2 string) (expval->any (run string)))

; value-of-program : Program -> ExpVal
(define (value-of-program pgm)
  (cases program pgm
    (a-program (e) (value-of e (init-env)))))

; value-of : Exp * Env -> ExpVal
(define (value-of exp env)
  (cases expression exp
    (const-exp (num)
               (num-val num))
    (var-exp (var)
             (apply-env var env))
    (diff-exp (exp1 exp2)
              (num-val (-
                        (expval->num (value-of exp1 env))
                        (expval->num (value-of exp2 env)))))
    (zero?-exp (exp)
               (if (= 0 (expval->num (value-of exp env)))
                   (bool-val #t)
                   (bool-val #f)))
    (if-exp (exp1 exp2 exp3)
            (if (eqv? #t (expval->bool (value-of exp1 env)))
                (value-of exp2 env)
                (value-of exp3 env)))
    (let-exp (var exp body)
             (value-of body (extend-env var (value-of exp env) env)))
    (proc-exp (var body)
              (proc-val (procedure var body env)))
    (call-exp (e1 e2)
              (apply-procedure
               (expval->proc (value-of e1 env))
               (value-of e2 env)))
    (letrec-exp (f x body letrec-body)
                (value-of letrec-body
                          (extend-env-rec f x body env)))
    (letrec*-exp (bindings body)
                 (value-of body (extend-env-rec* bindings env)))))